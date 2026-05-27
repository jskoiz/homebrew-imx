#!/usr/bin/env bash
set -euo pipefail

formula="${1:-Formula/imx.rb}"
work_dir="${IMX_FORMULA_SMOKE_DIR:-target/formula-archive-smoke}"
static_only="${IMX_FORMULA_STATIC_ONLY:-0}"

if [[ ! -f "$formula" ]]; then
  echo "error: formula not found: $formula" >&2
  exit 2
fi
if grep -Eq '^[[:space:]]*on_macos[[:space:]]+do\b' "$formula"; then
  echo "error: hosted tap verification is Linux-only; remove on_macos formula stanzas or use explicit local/manual macOS proof" >&2
  exit 1
fi

download() {
  local url="$1"
  local output="$2"
  if command -v curl >/dev/null 2>&1; then
    curl --retry 8 --retry-delay 3 --retry-all-errors -fsSL "$url" -o "$output"
  elif command -v wget >/dev/null 2>&1; then
    local attempt
    for attempt in 1 2 3 4 5 6 7 8; do
      if wget -qO "$output" "$url"; then
        return 0
      fi
      sleep 3
    done
    return 1
  else
    echo "error: curl or wget is required" >&2
    exit 2
  fi
}

verify_sha256() {
  local sha="$1"
  local file="$2"
  if command -v sha256sum >/dev/null 2>&1; then
    printf '%s  %s\n' "$sha" "$file" | sha256sum -c -
  elif command -v shasum >/dev/null 2>&1; then
    printf '%s  %s\n' "$sha" "$file" | shasum -a 256 -c -
  else
    echo "error: sha256sum or shasum is required" >&2
    exit 2
  fi
}

records_file="$(mktemp)"
trap 'rm -f "$records_file"' EXIT
ruby - "$formula" >"$records_file" <<'RUBY'
formula = ARGV.fetch(0)
stack = []
records = Hash.new { |hash, key| hash[key] = {} }

File.readlines(formula).each do |line|
  case line
  when /^\s*on_(macos|linux)\s+do\b/
    stack << [:os, Regexp.last_match(1)]
  when /^\s*on_(arm|intel)\s+do\b/
    stack << [:arch, Regexp.last_match(1)]
  when /^\s*end\b/
    stack.pop
  when /^\s*url\s+"([^"]+)"/
    os = stack.reverse.find { |kind, _| kind == :os }&.last
    arch = stack.reverse.find { |kind, _| kind == :arch }&.last
    records[[os, arch]][:url] = Regexp.last_match(1) if os && arch
  when /^\s*sha256\s+"([0-9a-f]{64})"/
    os = stack.reverse.find { |kind, _| kind == :os }&.last
    arch = stack.reverse.find { |kind, _| kind == :arch }&.last
    records[[os, arch]][:sha] = Regexp.last_match(1) if os && arch
  end
end

targets = {
  "intel" => "x86_64-unknown-linux-gnu",
  "arm" => "aarch64-unknown-linux-gnu",
}

records.each do |(os, arch), record|
  next unless os == "linux"
  target = targets[arch]
  next unless target
  abort "incomplete linux #{arch} archive stanza" unless record[:url] && record[:sha]
  puts [target, record[:url], record[:sha]].join("\t")
end
RUBY

if [[ ! -s "$records_file" ]]; then
  echo "error: formula declares no Linux archive stanzas" >&2
  exit 1
fi

rm -rf "$work_dir"
mkdir -p "$work_dir"

while IFS=$'\t' read -r target url sha; do
  case "$target" in
    x86_64-unknown-linux-gnu|aarch64-unknown-linux-gnu) ;;
    *)
      echo "error: unsupported Linux formula target: $target" >&2
      exit 1
      ;;
  esac
  if [[ "$url" != *"$target.tar.gz" ]]; then
    echo "error: formula URL does not match $target: $url" >&2
    exit 1
  fi

  archive_name="${url##*/}"
  version="${archive_name#imx-preview-}"
  version="${version%-$target.tar.gz}"
  if [[ -z "$version" || "$version" == "$archive_name" ]]; then
    echo "error: could not derive version from archive: $archive_name" >&2
    exit 1
  fi

  target_dir="$work_dir/$target"
  mkdir -p "$target_dir/extract"
  archive="$target_dir/$archive_name"
  download "$url" "$archive"
  verify_sha256 "$sha" "$archive"
  tar -xzf "$archive" -C "$target_dir/extract"
  binary="$target_dir/extract/imx-preview-$version-$target/imx"
  if [[ ! -x "$binary" ]]; then
    echo "error: archive did not contain executable binary: $binary" >&2
    exit 1
  fi

  file "$binary" | tee "$target_dir/file.txt"
  case "$target" in
    x86_64-unknown-linux-gnu)
      grep -Eiq 'x86-64|x86_64|amd64' "$target_dir/file.txt"
      runner=()
      linkage_command=(ldd)
      ;;
    aarch64-unknown-linux-gnu)
      grep -Eiq 'aarch64|arm64' "$target_dir/file.txt"
      read -r -a runner <<<"${IMX_FORMULA_ARM64_RUNNER:-qemu-aarch64 -L /usr/aarch64-linux-gnu}"
      read -r -a linkage_command <<<"${IMX_FORMULA_ARM64_LINKAGE:-aarch64-linux-gnu-readelf -d}"
      if [[ -z "${QEMU_LD_PREFIX:-}" ]]; then
        for ((i = 0; i < ${#runner[@]} - 1; i++)); do
          if [[ "${runner[$i]}" == "-L" ]]; then
            export QEMU_LD_PREFIX="${runner[$((i + 1))]}"
            break
          fi
        done
      fi
      ;;
  esac

  if [[ "$static_only" == 1 ]]; then
    continue
  fi

  if ((${#runner[@]})); then
    if ! command -v "${runner[0]}" >/dev/null 2>&1; then
      echo "error: ${runner[0]} is required to smoke $target" >&2
      exit 2
    fi
  elif [[ "$(uname -s):$(uname -m)" != Linux:x86_64 ]]; then
    echo "error: native Linux x86_64 host required to smoke $target; set IMX_FORMULA_STATIC_ONLY=1 for checksum-only validation" >&2
    exit 2
  fi
  if ! command -v "${linkage_command[0]}" >/dev/null 2>&1; then
    echo "error: ${linkage_command[0]} is required to inspect $target linkage" >&2
    exit 2
  fi

  run_binary() {
    if ((${#runner[@]})); then
      "${runner[@]}" "$binary" "$@"
    else
      "$binary" "$@"
    fi
  }

  version_output="$(run_binary --version)"
  if [[ "$version_output" != "imx $version" ]]; then
    echo "error: expected imx $version, got $version_output" >&2
    exit 1
  fi
  if [[ "$version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
    major="${BASH_REMATCH[1]}"
    minor="${BASH_REMATCH[2]}"
    if ((major > 0 || minor >= 17)); then
      run_binary self-test
    fi
  fi
  "${linkage_command[@]}" "$binary" | tee "$target_dir/linkage.txt"
  ! grep -E 'Magick(Core|Wand)|ImageMagick' "$target_dir/linkage.txt"

  smoke_dir="$target_dir/smoke"
  mkdir -p "$smoke_dir"
  printf 'P3\n2 2\n255\n255 0 0 0 255 0 0 0 255 255 255 255\n' >"$smoke_dir/input.ppm"
  printf 'P3\n2 1\n255\n255 0 0 0 0 255\n' >"$smoke_dir/fit-input.ppm"
  printf 'P2\n2 2\n255\n0 85 170 255\n' >"$smoke_dir/input.pgm"
  printf 'P1\n2 2\n0 1\n1 0\n' >"$smoke_dir/input.pbm"
  run_binary identify "$smoke_dir/input.ppm" | tee "$smoke_dir/identify-ppm.txt"
  grep -Fx 'format=PPM width=2 height=2 channels=RGB depth=8' "$smoke_dir/identify-ppm.txt"
  run_binary identify "$smoke_dir/input.pgm" | tee "$smoke_dir/identify-pgm.txt"
  grep -Fx 'format=PGM width=2 height=2 channels=GRAY depth=8' "$smoke_dir/identify-pgm.txt"
  run_binary identify "$smoke_dir/input.pbm" | tee "$smoke_dir/identify-pbm.txt"
  grep -Fx 'format=PBM width=2 height=2 channels=GRAY depth=1' "$smoke_dir/identify-pbm.txt"
  run_binary identify "PPM:$smoke_dir/input.ppm" | tee "$smoke_dir/identify-prefix-ppm.txt"
  grep -Fx 'format=PPM width=2 height=2 channels=RGB depth=8' "$smoke_dir/identify-prefix-ppm.txt"
  run_binary identify "PGM:$smoke_dir/input.pgm" | tee "$smoke_dir/identify-prefix-pgm.txt"
  grep -Fx 'format=PGM width=2 height=2 channels=GRAY depth=8' "$smoke_dir/identify-prefix-pgm.txt"
  run_binary identify "PBM:$smoke_dir/input.pbm" | tee "$smoke_dir/identify-prefix-pbm.txt"
  grep -Fx 'format=PBM width=2 height=2 channels=GRAY depth=1' "$smoke_dir/identify-prefix-pbm.txt"
  run_binary resize 1x1 "PPM:$smoke_dir/input.ppm" "PPM:$smoke_dir/resized.ppm"
  run_binary identify "PPM:$smoke_dir/resized.ppm" | tee "$smoke_dir/identify-resized-ppm.txt"
  grep -Fx 'format=PPM width=1 height=1 channels=RGB depth=8' "$smoke_dir/identify-resized-ppm.txt"
  run_binary resize-fit 5x5 "PPM:$smoke_dir/fit-input.ppm" "PPM:$smoke_dir/fit.ppm"
  run_binary identify "PPM:$smoke_dir/fit.ppm" | tee "$smoke_dir/identify-fit-ppm.txt"
  grep -Fx 'format=PPM width=5 height=3 channels=RGB depth=8' "$smoke_dir/identify-fit-ppm.txt"
  cp "$smoke_dir/fit-input.ppm" "$smoke_dir/batch-ppm.ppm"
  cp "$smoke_dir/input.pgm" "$smoke_dir/batch-pgm.pgm"
  mkdir -p "$smoke_dir/batch"
  run_binary batch-convert --to PPM --output-dir "$smoke_dir/batch" --resize-fit 5x5 "PPM:$smoke_dir/batch-ppm.ppm" "PGM:$smoke_dir/batch-pgm.pgm"
  run_binary identify "PPM:$smoke_dir/batch/batch-ppm.ppm" | tee "$smoke_dir/identify-batch-ppm.txt"
  grep -Fx 'format=PPM width=5 height=3 channels=RGB depth=8' "$smoke_dir/identify-batch-ppm.txt"
  run_binary identify "PPM:$smoke_dir/batch/batch-pgm.ppm" | tee "$smoke_dir/identify-batch-pgm.txt"
  grep -Fx 'format=PPM width=5 height=5 channels=RGB depth=8' "$smoke_dir/identify-batch-pgm.txt"
  run_binary "$smoke_dir/input.ppm" "$smoke_dir/output.bmp"
  run_binary identify "BMP:$smoke_dir/output.bmp" | tee "$smoke_dir/identify-bmp.txt"
  grep -Fx 'format=BMP width=2 height=2 channels=RGB depth=8' "$smoke_dir/identify-bmp.txt"
  run_binary "BMP:$smoke_dir/output.bmp" "PPM:$smoke_dir/bmp-output.ppm"
  run_binary identify "PPM:$smoke_dir/bmp-output.ppm" | tee "$smoke_dir/identify-bmp-output-ppm.txt"
  grep -Fx 'format=PPM width=2 height=2 channels=RGB depth=8' "$smoke_dir/identify-bmp-output-ppm.txt"
  run_binary resize 1x1 "BMP:$smoke_dir/output.bmp" "BMP:$smoke_dir/resized.bmp"
  run_binary identify "BMP:$smoke_dir/resized.bmp" | tee "$smoke_dir/identify-resized-bmp.txt"
  grep -Fx 'format=BMP width=1 height=1 channels=RGB depth=8' "$smoke_dir/identify-resized-bmp.txt"
  run_binary "$smoke_dir/fit-input.ppm" "$smoke_dir/fit-source.bmp"
  run_binary resize-fit 5x5 "BMP:$smoke_dir/fit-source.bmp" "BMP:$smoke_dir/fit.bmp"
  run_binary identify "BMP:$smoke_dir/fit.bmp" | tee "$smoke_dir/identify-fit-bmp.txt"
  grep -Fx 'format=BMP width=5 height=3 channels=RGB depth=8' "$smoke_dir/identify-fit-bmp.txt"
  mkdir -p "$smoke_dir/batch-bmp"
  run_binary batch-convert --to BMP --output-dir "$smoke_dir/batch-bmp" --resize-fit 5x5 "PPM:$smoke_dir/batch-ppm.ppm" "PGM:$smoke_dir/batch-pgm.pgm"
  run_binary identify "BMP:$smoke_dir/batch-bmp/batch-ppm.bmp" | tee "$smoke_dir/identify-batch-bmp-ppm.txt"
  grep -Fx 'format=BMP width=5 height=3 channels=RGB depth=8' "$smoke_dir/identify-batch-bmp-ppm.txt"
  run_binary identify "BMP:$smoke_dir/batch-bmp/batch-pgm.bmp" | tee "$smoke_dir/identify-batch-bmp-pgm.txt"
  grep -Fx 'format=BMP width=5 height=5 channels=RGB depth=8' "$smoke_dir/identify-batch-bmp-pgm.txt"
  run_binary "$smoke_dir/input.ppm" "$smoke_dir/output.qoi"
  run_binary identify "$smoke_dir/output.qoi" | tee "$smoke_dir/identify-qoi.txt"
  grep -Fx 'format=QOI width=2 height=2 channels=RGBA depth=8' "$smoke_dir/identify-qoi.txt"
  run_binary identify "QOI:$smoke_dir/output.qoi" | tee "$smoke_dir/identify-prefix-qoi.txt"
  grep -Fx 'format=QOI width=2 height=2 channels=RGBA depth=8' "$smoke_dir/identify-prefix-qoi.txt"
  run_binary "$smoke_dir/output.qoi" "$smoke_dir/output.ff"
  run_binary identify "$smoke_dir/output.ff" | tee "$smoke_dir/identify-farbfeld.txt"
  grep -Fx 'format=FARBFELD width=2 height=2 channels=RGBA depth=16' "$smoke_dir/identify-farbfeld.txt"
  run_binary identify "FARBFELD:$smoke_dir/output.ff" | tee "$smoke_dir/identify-prefix-farbfeld.txt"
  grep -Fx 'format=FARBFELD width=2 height=2 channels=RGBA depth=16' "$smoke_dir/identify-prefix-farbfeld.txt"
  run_binary "$smoke_dir/output.ff" "$smoke_dir/output.pbm"
  run_binary "$smoke_dir/output.ff" "$smoke_dir/output.pgm"
  run_binary "$smoke_dir/output.ff" "$smoke_dir/output.png"
  run_binary "$smoke_dir/output.ff" "$smoke_dir/output.ppm"
  run_binary "$smoke_dir/input.ppm" "$smoke_dir/output.jpg"
  run_binary identify "$smoke_dir/output.jpg" | tee "$smoke_dir/identify-jpeg.txt"
  grep -Fx 'format=JPEG width=2 height=2 channels=RGB depth=8' "$smoke_dir/identify-jpeg.txt"
  run_binary identify "JPEG:$smoke_dir/output.jpg" | tee "$smoke_dir/identify-prefix-jpeg.txt"
  grep -Fx 'format=JPEG width=2 height=2 channels=RGB depth=8' "$smoke_dir/identify-prefix-jpeg.txt"
  printf 'P3\n2 1\n255\n255 0 0 0 0 255\n' >"$smoke_dir/orientation-source.ppm"
  run_binary "$smoke_dir/orientation-source.ppm" "$smoke_dir/orientation-source.jpg"
  python3 - "$smoke_dir/orientation-source.jpg" "$smoke_dir/oriented-o6.jpg" <<'PY'
import sys

source, output = sys.argv[1:3]
jpeg = open(source, "rb").read()
app1 = (
    b"Exif\0\0MM\0*\0\0\0\x08"
    + (1).to_bytes(2, "big")
    + (0x0112).to_bytes(2, "big")
    + (3).to_bytes(2, "big")
    + (1).to_bytes(4, "big")
    + (6).to_bytes(2, "big")
    + b"\0\0"
    + (0).to_bytes(4, "big")
)
segment = b"\xff\xe1" + (len(app1) + 2).to_bytes(2, "big") + app1
open(output, "wb").write(jpeg[:2] + segment + jpeg[2:])
PY
  run_binary identify "JPEG:$smoke_dir/oriented-o6.jpg" | tee "$smoke_dir/identify-orientation-jpeg.txt"
  grep -Fx 'format=JPEG width=1 height=2 channels=RGB depth=8' "$smoke_dir/identify-orientation-jpeg.txt"
  run_binary "JPEG:$smoke_dir/oriented-o6.jpg" "PPM:$smoke_dir/oriented-o6.ppm"
  run_binary identify "PPM:$smoke_dir/oriented-o6.ppm" | tee "$smoke_dir/identify-orientation-ppm.txt"
  grep -Fx 'format=PPM width=1 height=2 channels=RGB depth=8' "$smoke_dir/identify-orientation-ppm.txt"
  python3 - "$smoke_dir/progressive-rgb.jpg" "$smoke_dir/progressive-o6.jpg" <<'PY'
import sys

rgb_output, oriented_output = sys.argv[1:3]
progressive_hex = (
    "ffd8ffe000104a46494600010100000100010000ffdb004300030202020202030202020303030304060404040404080606050609080a0a090809090a0c0f0c0a0b0e0b09090d110d0e0f101011100a0c12131210130f101010"
    "ffdb00430103030304030408040408100b090b1010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010ffc20011080003000403011100021101031101"
    "ffc40014000100000000000000000000000000000006ffc4001501010100000000000000000000000000000205ffda000c030100021003100000011d347fffc4001510010100000000000000000000000000000503"
    "ffda000801010001050265140ca7ffc4001f1100020005050000000000000000000000010200030531411112131421ffda0008010301013f01a5d427f5f9491ba616763a0f59c96636c936b0c47f"
    "ffc4001f1100020005050000000000000000000000010200041112210305142271ffda0008010201013f01e34b6e88af39a28c56e03a2e05ec683181524fa498ffc4001c1000030002030100000000000000000000010203041100058191"
    "ffda0008010100063f02c75ebb36f8cb680a389d0a82db2bbf8aa3ce7fffc400161001010100000000000000000000000000011100ffda0008010100013f2111a3b847819763ffda000c030100020003000000103f"
    "ffc4001811010100030000000000000000000000000111002131ffda0008010301013f104d4241dd88295313800033ffc4001811010100030000000000000000000000000121001131ffda0008010201013f106ca63d7160487003d0573f"
    "ffc400161001010100000000000000000000000000011121ffda0008010100013f1066307afe986b00a05ad5ffd9"
)
progressive = bytes.fromhex(progressive_hex)
app1 = (
    b"Exif\0\0MM\0*\0\0\0\x08"
    + (1).to_bytes(2, "big")
    + (0x0112).to_bytes(2, "big")
    + (3).to_bytes(2, "big")
    + (1).to_bytes(4, "big")
    + (6).to_bytes(2, "big")
    + b"\0\0"
    + (0).to_bytes(4, "big")
)
segment = b"\xff\xe1" + (len(app1) + 2).to_bytes(2, "big") + app1
open(rgb_output, "wb").write(progressive)
open(oriented_output, "wb").write(progressive[:2] + segment + progressive[2:])
PY
  run_binary identify "JPEG:$smoke_dir/progressive-rgb.jpg" | tee "$smoke_dir/identify-progressive-jpeg.txt"
  grep -Fx 'format=JPEG width=4 height=3 channels=RGB depth=8' "$smoke_dir/identify-progressive-jpeg.txt"
  run_binary "JPEG:$smoke_dir/progressive-rgb.jpg" "PPM:$smoke_dir/progressive-rgb.ppm"
  run_binary identify "PPM:$smoke_dir/progressive-rgb.ppm" | tee "$smoke_dir/identify-progressive-ppm.txt"
  grep -Fx 'format=PPM width=4 height=3 channels=RGB depth=8' "$smoke_dir/identify-progressive-ppm.txt"
  run_binary identify "JPEG:$smoke_dir/progressive-o6.jpg" | tee "$smoke_dir/identify-progressive-orientation-jpeg.txt"
  grep -Fx 'format=JPEG width=3 height=4 channels=RGB depth=8' "$smoke_dir/identify-progressive-orientation-jpeg.txt"
  run_binary "JPEG:$smoke_dir/progressive-o6.jpg" "PPM:$smoke_dir/progressive-o6.ppm"
  run_binary identify "PPM:$smoke_dir/progressive-o6.ppm" | tee "$smoke_dir/identify-progressive-orientation-ppm.txt"
  grep -Fx 'format=PPM width=3 height=4 channels=RGB depth=8' "$smoke_dir/identify-progressive-orientation-ppm.txt"
  run_binary "JPEG:$smoke_dir/output.jpg" "FARBFELD:$smoke_dir/jpeg-output.ff"
  run_binary identify "FARBFELD:$smoke_dir/jpeg-output.ff" | tee "$smoke_dir/identify-jpeg-output-farbfeld.txt"
  grep -Fx 'format=FARBFELD width=2 height=2 channels=RGBA depth=16' "$smoke_dir/identify-jpeg-output-farbfeld.txt"
  run_binary "PPM:$smoke_dir/input.ppm" "FARBFELD:$smoke_dir/prefix-output.ff"
  run_binary "PPM:$smoke_dir/input.ppm" "JPEG:$smoke_dir/prefix-output.jpg"
  run_binary "JPEG:$smoke_dir/prefix-output.jpg" "FARBFELD:$smoke_dir/prefix-jpeg-output.ff"
  run_binary "FARBFELD:$smoke_dir/prefix-output.ff" "QOI:$smoke_dir/prefix-output.qoi"
  run_binary "FARBFELD:$smoke_dir/prefix-output.ff" "PBM:$smoke_dir/prefix-output.pbm"
  run_binary "FARBFELD:$smoke_dir/prefix-output.ff" "PGM:$smoke_dir/prefix-output.pgm"
  run_binary "FARBFELD:$smoke_dir/prefix-output.ff" "PNG:$smoke_dir/prefix-output.png"
  run_binary "FARBFELD:$smoke_dir/prefix-output.ff" "PPM:$smoke_dir/prefix-output.ppm"
  run_binary "FARBFELD:$smoke_dir/prefix-output.ff" "BMP:$smoke_dir/prefix-output.bmp"
  run_binary "$smoke_dir/output.ff" "$smoke_dir/rewrite.ff"
  run_binary "$smoke_dir/output.bmp" "$smoke_dir/rewrite.bmp"
  run_binary "$smoke_dir/output.jpg" "$smoke_dir/rewrite.jpg"
  run_binary "$smoke_dir/output.qoi" "$smoke_dir/rewrite.qoi"
  run_binary "$smoke_dir/input.pbm" "$smoke_dir/rewrite.pbm"
  run_binary "$smoke_dir/input.pgm" "$smoke_dir/rewrite.pgm"
  run_binary "$smoke_dir/output.png" "$smoke_dir/rewrite.png"
  run_binary "$smoke_dir/input.ppm" "$smoke_dir/rewrite.ppm"
  run_binary identify "$smoke_dir/output.pbm" | tee "$smoke_dir/identify-output-pbm.txt"
  grep -Fx 'format=PBM width=2 height=2 channels=GRAY depth=1' "$smoke_dir/identify-output-pbm.txt"
  run_binary identify "$smoke_dir/output.pgm" | tee "$smoke_dir/identify-output-pgm.txt"
  grep -Fx 'format=PGM width=2 height=2 channels=GRAY depth=16' "$smoke_dir/identify-output-pgm.txt"
  run_binary identify "$smoke_dir/output.png" | tee "$smoke_dir/identify-output-png.txt"
  grep -Fx 'format=PNG width=2 height=2 channels=RGBA depth=16' "$smoke_dir/identify-output-png.txt"
  run_binary identify "$smoke_dir/output.ppm" | tee "$smoke_dir/identify-output-ppm.txt"
  grep -Fx 'format=PPM width=2 height=2 channels=RGB depth=16' "$smoke_dir/identify-output-ppm.txt"
  run_binary identify "$smoke_dir/rewrite.ff" | tee "$smoke_dir/identify-rewrite-farbfeld.txt"
  grep -Fx 'format=FARBFELD width=2 height=2 channels=RGBA depth=16' "$smoke_dir/identify-rewrite-farbfeld.txt"
  run_binary identify "$smoke_dir/rewrite.bmp" | tee "$smoke_dir/identify-rewrite-bmp.txt"
  grep -Fx 'format=BMP width=2 height=2 channels=RGB depth=8' "$smoke_dir/identify-rewrite-bmp.txt"
  run_binary identify "$smoke_dir/rewrite.jpg" | tee "$smoke_dir/identify-rewrite-jpeg.txt"
  grep -Fx 'format=JPEG width=2 height=2 channels=RGB depth=8' "$smoke_dir/identify-rewrite-jpeg.txt"
  run_binary identify "$smoke_dir/rewrite.qoi" | tee "$smoke_dir/identify-rewrite-qoi.txt"
  grep -Fx 'format=QOI width=2 height=2 channels=RGBA depth=8' "$smoke_dir/identify-rewrite-qoi.txt"
  run_binary identify "$smoke_dir/rewrite.pbm" | tee "$smoke_dir/identify-rewrite-pbm.txt"
  grep -Fx 'format=PBM width=2 height=2 channels=GRAY depth=1' "$smoke_dir/identify-rewrite-pbm.txt"
  run_binary identify "$smoke_dir/rewrite.pgm" | tee "$smoke_dir/identify-rewrite-pgm.txt"
  grep -Fx 'format=PGM width=2 height=2 channels=GRAY depth=8' "$smoke_dir/identify-rewrite-pgm.txt"
  run_binary identify "$smoke_dir/rewrite.png" | tee "$smoke_dir/identify-rewrite-png.txt"
  grep -Fx 'format=PNG width=2 height=2 channels=RGBA depth=16' "$smoke_dir/identify-rewrite-png.txt"
  run_binary identify "$smoke_dir/rewrite.ppm" | tee "$smoke_dir/identify-rewrite-ppm.txt"
  grep -Fx 'format=PPM width=2 height=2 channels=RGB depth=8' "$smoke_dir/identify-rewrite-ppm.txt"
  run_binary identify "QOI:$smoke_dir/prefix-output.qoi" | tee "$smoke_dir/identify-prefix-output-qoi.txt"
  grep -Fx 'format=QOI width=2 height=2 channels=RGBA depth=8' "$smoke_dir/identify-prefix-output-qoi.txt"
  run_binary identify "JPEG:$smoke_dir/prefix-output.jpg" | tee "$smoke_dir/identify-prefix-output-jpeg.txt"
  grep -Fx 'format=JPEG width=2 height=2 channels=RGB depth=8' "$smoke_dir/identify-prefix-output-jpeg.txt"
  run_binary identify "PBM:$smoke_dir/prefix-output.pbm" | tee "$smoke_dir/identify-prefix-output-pbm.txt"
  grep -Fx 'format=PBM width=2 height=2 channels=GRAY depth=1' "$smoke_dir/identify-prefix-output-pbm.txt"
  run_binary identify "PGM:$smoke_dir/prefix-output.pgm" | tee "$smoke_dir/identify-prefix-output-pgm.txt"
  grep -Fx 'format=PGM width=2 height=2 channels=GRAY depth=16' "$smoke_dir/identify-prefix-output-pgm.txt"
  run_binary identify "PNG:$smoke_dir/prefix-output.png" | tee "$smoke_dir/identify-prefix-output-png.txt"
  grep -Fx 'format=PNG width=2 height=2 channels=RGBA depth=16' "$smoke_dir/identify-prefix-output-png.txt"
  run_binary identify "PPM:$smoke_dir/prefix-output.ppm" | tee "$smoke_dir/identify-prefix-output-ppm.txt"
  grep -Fx 'format=PPM width=2 height=2 channels=RGB depth=16' "$smoke_dir/identify-prefix-output-ppm.txt"
  run_binary identify "BMP:$smoke_dir/prefix-output.bmp" | tee "$smoke_dir/identify-prefix-output-bmp.txt"
  grep -Fx 'format=BMP width=2 height=2 channels=RGBA depth=8' "$smoke_dir/identify-prefix-output-bmp.txt"
done <"$records_file"

echo "$work_dir"

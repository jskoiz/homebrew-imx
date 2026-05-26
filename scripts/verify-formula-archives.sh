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
  "${linkage_command[@]}" "$binary" | tee "$target_dir/linkage.txt"
  ! grep -E 'Magick(Core|Wand)|ImageMagick' "$target_dir/linkage.txt"

  smoke_dir="$target_dir/smoke"
  mkdir -p "$smoke_dir"
  printf 'P3\n2 2\n255\n255 0 0 0 255 0 0 0 255 255 255 255\n' >"$smoke_dir/input.ppm"
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
  run_binary "PPM:$smoke_dir/input.ppm" "FARBFELD:$smoke_dir/prefix-output.ff"
  run_binary "FARBFELD:$smoke_dir/prefix-output.ff" "QOI:$smoke_dir/prefix-output.qoi"
  run_binary "FARBFELD:$smoke_dir/prefix-output.ff" "PBM:$smoke_dir/prefix-output.pbm"
  run_binary "FARBFELD:$smoke_dir/prefix-output.ff" "PGM:$smoke_dir/prefix-output.pgm"
  run_binary "FARBFELD:$smoke_dir/prefix-output.ff" "PNG:$smoke_dir/prefix-output.png"
  run_binary "FARBFELD:$smoke_dir/prefix-output.ff" "PPM:$smoke_dir/prefix-output.ppm"
  run_binary "$smoke_dir/output.ff" "$smoke_dir/rewrite.ff"
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
  run_binary identify "PBM:$smoke_dir/prefix-output.pbm" | tee "$smoke_dir/identify-prefix-output-pbm.txt"
  grep -Fx 'format=PBM width=2 height=2 channels=GRAY depth=1' "$smoke_dir/identify-prefix-output-pbm.txt"
  run_binary identify "PGM:$smoke_dir/prefix-output.pgm" | tee "$smoke_dir/identify-prefix-output-pgm.txt"
  grep -Fx 'format=PGM width=2 height=2 channels=GRAY depth=16' "$smoke_dir/identify-prefix-output-pgm.txt"
  run_binary identify "PNG:$smoke_dir/prefix-output.png" | tee "$smoke_dir/identify-prefix-output-png.txt"
  grep -Fx 'format=PNG width=2 height=2 channels=RGBA depth=16' "$smoke_dir/identify-prefix-output-png.txt"
  run_binary identify "PPM:$smoke_dir/prefix-output.ppm" | tee "$smoke_dir/identify-prefix-output-ppm.txt"
  grep -Fx 'format=PPM width=2 height=2 channels=RGB depth=16' "$smoke_dir/identify-prefix-output-ppm.txt"
done <"$records_file"

echo "$work_dir"

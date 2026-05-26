#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 1 ]]; then
  echo "usage: update-imx-formula.sh <version>" >&2
  exit 2
fi

version="$1"
if [[ "$version" != v* ]]; then
  version="v$version"
fi
formula_version="${version#v}"
prefix_smoke_required=0
if [[ "$formula_version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)$ ]]; then
  major="${BASH_REMATCH[1]}"
  minor="${BASH_REMATCH[2]}"
  if ((major > 0 || minor >= 6)); then
    prefix_smoke_required=1
  fi
fi

repo="${IMX_REPO:-jskoiz/imx}"
output="${IMX_FORMULA_OUTPUT:-Formula/imx.rb}"
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT

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

download "https://github.com/$repo/releases/download/$version/SHA256SUMS" "$work_dir/SHA256SUMS"
if [[ -n "${IMX_GENERATOR_PATH:-}" ]]; then
  cp "$IMX_GENERATOR_PATH" "$work_dir/generate-homebrew-formula.sh"
else
  download "https://raw.githubusercontent.com/$repo/$version/scripts/generate-homebrew-formula.sh" "$work_dir/generate-homebrew-formula.sh"
fi

awk '
  NF != 2 || $1 !~ /^[0-9a-f]{64}$/ || $2 !~ /^imx-preview-[0-9]+\.[0-9]+\.[0-9]+-.+\.tar\.gz$/ {
    print "error: invalid SHA256SUMS line: " $0 > "/dev/stderr"
    exit 1
  }
' "$work_dir/SHA256SUMS"

tmp_formula="$work_dir/imx.rb"
bash "$work_dir/generate-homebrew-formula.sh" "$version" "$work_dir/SHA256SUMS" "$tmp_formula"
ruby -c "$tmp_formula"
if ! grep -Fq 'format=QOI width=2 height=1 channels=RGBA depth=8' "$tmp_formula"; then
  echo "error: generated formula does not contain the current QOI RGBA smoke expectation" >&2
  exit 1
fi
if [[ "$prefix_smoke_required" == 1 ]] && ! grep -Fq 'PPM:input.ppm' "$tmp_formula"; then
  echo "error: generated formula does not contain the required prefix smoke expectation" >&2
  exit 1
fi
bash scripts/check-no-hosted-apple-actions.sh

if grep -Fq 'aarch64-unknown-linux-gnu' "$tmp_formula" && [[ "${IMX_UPDATE_VERIFY_ARCHIVES:-0}" != 1 ]]; then
  echo "error: generated formula includes Linux arm64; rerun on Linux with IMX_UPDATE_VERIFY_ARCHIVES=1 so the tap claim is verified" >&2
  exit 1
fi

if [[ "${IMX_UPDATE_VERIFY_ARCHIVES:-0}" == 1 ]]; then
  bash scripts/verify-formula-archives.sh "$tmp_formula"
fi

cp "$tmp_formula" "$output"
ruby -c "$output"
if [[ "${IMX_UPDATE_BREW_STYLE:-0}" == 1 ]] && command -v brew >/dev/null 2>&1; then
  HOMEBREW_NO_AUTO_UPDATE=1 brew style "$output"
fi

echo "Updated $output from $repo $version."

# IMX Homebrew Tap

This is the Homebrew tap for [IMX](https://github.com/jskoiz/imx), a standalone
Rust image tool built one ImageMagick-compatible slice at a time.

## Install

```sh
brew tap jskoiz/imx
brew install imx
imx --version
```

The `imx` formula installs the published IMX `v0.12.0` release archive for the
current supported platform and verifies the release archive checksum declared in
the formula. Published Linux archives require glibc 2.34 or newer.

Supported tap targets:

- Linux x86_64
- Linux arm64

No Homebrew/core submission, macOS v0.12.0 tap support, Windows archive,
crates.io package, APNG/indexed/low-bit PNG, CMYK/high-depth JPEG, progressive
JPEG output, EXIF writing or preservation, GPS handling, color-management/profile
transforms, MagickCore/MagickWand API, or full ImageMagick CLI compatibility is
claimed by the current v0.12.0 tap formula.

Tap GitHub Actions run a Linux-only formula/archive smoke. macOS install proof
must be run locally or manually after explicit approval; normal pushes, pull
requests, schedules, and tap updates must not trigger hosted macOS or iOS
runners.

Tap updates are automation for the `jskoiz/homebrew-imx` tap only. They do not
submit to Homebrew/core and must not trigger hosted macOS or iOS GitHub Actions;
macOS tap proof remains local/manual unless explicitly approved.

Linux arm64 tap support is generated from the published v0.12.0 `SHA256SUMS` and
verified by Linux-only archive smoke. macOS tap support may be added only after a
published macOS release archive exists and local/manual macOS proof is recorded
after explicit approval.

## Smoke Test

```sh
brew test imx
imx identify path/to/input.ppm
```

The formula test identifies a small PPM fixture, transcodes it to QOI, PNG, and
JPEG, checks exact `PPM:`, `QOI:`, `PNG:`, `JPEG:`, and `FARBFELD:` prefixes,
checks JPEG EXIF Orientation 6 identify/transcode normalization, checks
progressive JPEG identify/transcode plus progressive Orientation 6
normalization, checks v0.12 PPM/PGM intake fixtures, and checks deterministic
PPM/JPEG same-format rewrites. The tap archive verifier additionally smokes
FARBFELD, JPEG, QOI, PBM, PGM, PNG, PPM,
16-bit PGM/PNG/PPM outputs, same-format rewrites, orientation normalization,
progressive JPEG input, v0.12 intake paths, and exact prefix identify/transcode
forms.

## Update

To refresh the tap after a future IMX release, run:

```sh
scripts/update-imx-formula.sh v0.12.0
```

The updater downloads the release `SHA256SUMS`, runs that release's formula
generator, validates formula syntax, and checks that this tap still has no
hosted Apple Actions references. If the generated formula includes Linux arm64,
rerun on Linux with `IMX_UPDATE_VERIFY_ARCHIVES=1` and the arm64 runtime smoke
dependencies: `binutils-aarch64-linux-gnu`, `libc6-arm64-cross`,
`libgcc-s1-arm64-cross`, and `qemu-user`.
Set `IMX_UPDATE_BREW_STYLE=1` to run `brew style` as an additional local check.
Set `IMX_GENERATOR_PATH=/path/to/generate-homebrew-formula.sh` only for local
pre-release testing of a generator that has not been tagged yet.

Before pushing a tap update, run:

```sh
bash scripts/check-no-hosted-apple-actions.sh
ruby -c Formula/imx.rb
IMX_FORMULA_STATIC_ONLY=1 bash scripts/verify-formula-archives.sh
```

## Remove

```sh
brew uninstall imx
brew untap jskoiz/imx
```

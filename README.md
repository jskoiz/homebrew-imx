# IMX Homebrew Tap

This is the Homebrew tap for [IMX](https://github.com/jskoiz/imx), a standalone
Rust image tool built one ImageMagick-compatible slice at a time.

## Install

```sh
brew tap jskoiz/imx
brew install imx
imx --version
```

The `imx` formula installs the published IMX `v0.4.0` release archive for the
current supported platform and verifies the release archive checksum declared in
the formula.

Supported tap targets:

- macOS arm64
- macOS x86_64
- Linux x86_64

No Homebrew/core submission, Linux arm64 archive, Windows archive, crates.io
package, new image format, MagickCore/MagickWand API, or full ImageMagick CLI
compatibility is claimed by this tap.

Tap GitHub Actions run a Linux-only formula/archive smoke. macOS install proof
must be run locally or manually after explicit approval; normal pushes, pull
requests, schedules, and tap updates must not trigger hosted macOS or iOS
runners.

## Smoke Test

```sh
brew test imx
imx identify path/to/input.ppm
```

The formula test identifies a small PPM fixture, transcodes it to QOI, and
identifies the QOI output.

## Update

To refresh the tap after a future IMX release, update `Formula/imx.rb` with the
new release archive URLs and SHA-256 values from the published `SHA256SUMS`
asset in `jskoiz/imx`.

Before pushing a tap update, run:

```sh
bash scripts/check-no-hosted-apple-actions.sh
```

## Remove

```sh
brew uninstall imx
brew untap jskoiz/imx
```

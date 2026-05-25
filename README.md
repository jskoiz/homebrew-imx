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

## Remove

```sh
brew uninstall imx
brew untap jskoiz/imx
```

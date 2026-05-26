class Imx < Formula
  desc "Standalone Rust image tool for ImageMagick-compatible slices"
  homepage "https://github.com/jskoiz/imx"
  license "ImageMagick"

  on_linux do
    on_intel do
      url "https://github.com/jskoiz/imx/releases/download/v0.8.0/imx-preview-0.8.0-x86_64-unknown-linux-gnu.tar.gz"
      sha256 "1bd1df0b08470d0ae0e1503d1fb24948d16a9a30fc13289ff6aff150e3a02b35"
    end

    on_arm do
      url "https://github.com/jskoiz/imx/releases/download/v0.8.0/imx-preview-0.8.0-aarch64-unknown-linux-gnu.tar.gz"
      sha256 "155d24661a6abe30b2911c8f1957644a07a3073bd6f68e877aafac1385a0dd13"
    end
  end

  def install
    bin.install "imx"
    prefix.install "README.md", "COMPATIBILITY.md", "RELEASE_NOTES.md", "PRODUCTION_READINESS.md"
  end

  test do
    (testpath/"input.ppm").write "P3\n2 1\n255\n255 0 0 0 0 255\n"
    assert_match "format=PPM width=2 height=1 channels=RGB depth=8", shell_output("#{bin/"imx"} identify input.ppm")
    system bin/"imx", "input.ppm", "output.qoi"
    assert_match "format=QOI width=2 height=1 channels=RGBA depth=8", shell_output("#{bin/"imx"} identify output.qoi")
    assert_match "format=PPM width=2 height=1 channels=RGB depth=8", shell_output("#{bin/"imx"} identify PPM:input.ppm")
    assert_match "format=QOI width=2 height=1 channels=RGBA depth=8", shell_output("#{bin/"imx"} identify QOI:output.qoi")
    system bin/"imx", "PPM:input.ppm", "FARBFELD:prefix-output.ff"
    assert_match "format=FARBFELD width=2 height=1 channels=RGBA depth=16", shell_output("#{bin/"imx"} identify FARBFELD:prefix-output.ff")
    system bin/"imx", "input.ppm", "output.png"
    assert_match "format=PNG width=2 height=1 channels=RGB depth=8", shell_output("#{bin/"imx"} identify PNG:output.png")
    system bin/"imx", "PNG:output.png", "FARBFELD:png-output.ff"
    assert_match "format=FARBFELD width=2 height=1 channels=RGBA depth=16", shell_output("#{bin/"imx"} identify png-output.ff")
    system bin/"imx", "input.ppm", "rewrite.ppm"
    assert_match "format=PPM width=2 height=1 channels=RGB depth=8", shell_output("#{bin/"imx"} identify rewrite.ppm")
  end
end

class Imx < Formula
  desc "Standalone Rust image tool for FARBFELD, QOI, and Netpbm transcodes"
  homepage "https://github.com/jskoiz/imx"
  license "ImageMagick"

  on_linux do
    on_intel do
      url "https://github.com/jskoiz/imx/releases/download/v0.5.0/imx-preview-0.5.0-x86_64-unknown-linux-gnu.tar.gz"
      sha256 "56c9a95d11ccc4029cddad3fec31fc84dbc909296d6f6e76d2865b177ad8d4a8"
    end

    on_arm do
      url "https://github.com/jskoiz/imx/releases/download/v0.5.0/imx-preview-0.5.0-aarch64-unknown-linux-gnu.tar.gz"
      sha256 "ccc3e7ad2435b719c2104f4c7b59daba9d831d304e31f5a2e8016bdf60d60f54"
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
    system bin/"imx", "input.ppm", "rewrite.ppm"
    assert_match "format=PPM width=2 height=1 channels=RGB depth=8", shell_output("#{bin/"imx"} identify rewrite.ppm")
  end
end

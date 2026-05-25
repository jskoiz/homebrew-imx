class Imx < Formula
  desc "Standalone Rust image tool for FARBFELD, QOI, and Netpbm transcodes"
  homepage "https://github.com/jskoiz/imx"
  license "ImageMagick"

  on_macos do
    on_arm do
      url "https://github.com/jskoiz/imx/releases/download/v0.4.0/imx-preview-0.4.0-aarch64-apple-darwin.tar.gz"
      sha256 "6a3727c9381ccdf055483fd79256dc018dc570355713fd42dbf8cb1b6bf11fbe"
    end

    on_intel do
      url "https://github.com/jskoiz/imx/releases/download/v0.4.0/imx-preview-0.4.0-x86_64-apple-darwin.tar.gz"
      sha256 "443d4aa3671dcdc38df4c8b9f57db96f5aff27bb3d3fceb84c46e912d8c1251d"
    end
  end

  on_linux do
    on_intel do
      url "https://github.com/jskoiz/imx/releases/download/v0.4.0/imx-preview-0.4.0-x86_64-unknown-linux-gnu.tar.gz"
      sha256 "6e3d8688621bfdf8ff36af5e6f607162698256ce48178c433adc0968db0d1762"
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
  end
end

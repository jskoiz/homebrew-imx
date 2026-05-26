class Imx < Formula
  desc "Standalone Rust image tool for FARBFELD, QOI, and Netpbm transcodes"
  homepage "https://github.com/jskoiz/imx"
  license "ImageMagick"

  on_linux do
    on_intel do
      url "https://github.com/jskoiz/imx/releases/download/v0.7.0/imx-preview-0.7.0-x86_64-unknown-linux-gnu.tar.gz"
      sha256 "85612b8a3dff4ed72c7018501b4ab2bcf6d64e1fb715ba11f4c05dd357417e85"
    end

    on_arm do
      url "https://github.com/jskoiz/imx/releases/download/v0.7.0/imx-preview-0.7.0-aarch64-unknown-linux-gnu.tar.gz"
      sha256 "04f5594a5955af74c07143c663f8c92834f6db9e4ab2b8eee58f0182feca08e8"
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
    assert_match "format=PPM width=2 height=1 channels=RGB depth=8",
                 shell_output("#{bin/"imx"} identify PPM:input.ppm")
    assert_match "format=QOI width=2 height=1 channels=RGBA depth=8",
                 shell_output("#{bin/"imx"} identify QOI:output.qoi")
    system bin/"imx", "PPM:input.ppm", "FARBFELD:prefix-output.ff"
    assert_match "format=FARBFELD width=2 height=1 channels=RGBA depth=16",
                 shell_output("#{bin/"imx"} identify FARBFELD:prefix-output.ff")
    system bin/"imx", "input.ppm", "rewrite.ppm"
    assert_match "format=PPM width=2 height=1 channels=RGB depth=8", shell_output("#{bin/"imx"} identify rewrite.ppm")
  end
end

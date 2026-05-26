class Imx < Formula
  desc "Standalone Rust image tool for ImageMagick-compatible slices"
  homepage "https://github.com/jskoiz/imx"
  license "ImageMagick"

  on_linux do
    on_intel do
      url "https://github.com/jskoiz/imx/releases/download/v0.10.0/imx-preview-0.10.0-x86_64-unknown-linux-gnu.tar.gz"
      sha256 "c4479f1a3ea7e4e145550b2e09273ebf399a89048d0d4382bacc27f9a2c10902"
    end

    on_arm do
      url "https://github.com/jskoiz/imx/releases/download/v0.10.0/imx-preview-0.10.0-aarch64-unknown-linux-gnu.tar.gz"
      sha256 "57f64497cc0f56c9956ea162eabd24f5f22cdbea033889af4aa0363386ffcebb"
    end
  end

  def install
    bin.install "imx"
    prefix.install "README.md", "COMPATIBILITY.md", "RELEASE_NOTES.md", "PRODUCTION_READINESS.md"
  end

  def caveats
    return unless OS.linux?

    "Published Linux archives require glibc 2.34 or newer."
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
    system bin/"imx", "input.ppm", "output.jpg"
    assert_match "format=JPEG width=2 height=1 channels=RGB depth=8", shell_output("#{bin/"imx"} identify JPEG:output.jpg")
    jpeg = File.binread("output.jpg")
    app1 = "Exif\0\0MM\0*\0\0\0\b".b + [1, 0x0112, 3, 1].pack("nnnN") + [6].pack("n") + "\0\0".b + [0].pack("N")
    segment = "\xff\xe1".b + [app1.bytesize + 2].pack("n") + app1
    File.binwrite("oriented-o6.jpg", jpeg.byteslice(0, 2) + segment + jpeg.byteslice(2, jpeg.bytesize - 2))
    assert_match "format=JPEG width=1 height=2 channels=RGB depth=8", shell_output("#{bin/"imx"} identify JPEG:oriented-o6.jpg")
    system bin/"imx", "JPEG:oriented-o6.jpg", "PPM:oriented-o6.ppm"
    assert_match "format=PPM width=1 height=2 channels=RGB depth=8", shell_output("#{bin/"imx"} identify PPM:oriented-o6.ppm")
    system bin/"imx", "JPEG:output.jpg", "FARBFELD:jpeg-output.ff"
    assert_match "format=FARBFELD width=2 height=1 channels=RGBA depth=16", shell_output("#{bin/"imx"} identify FARBFELD:jpeg-output.ff")
    system bin/"imx", "JPEG:output.jpg", "JPEG:rewrite.jpg"
    assert_match "format=JPEG width=2 height=1 channels=RGB depth=8", shell_output("#{bin/"imx"} identify rewrite.jpg")
    system bin/"imx", "input.ppm", "rewrite.ppm"
    assert_match "format=PPM width=2 height=1 channels=RGB depth=8", shell_output("#{bin/"imx"} identify rewrite.ppm")
  end
end

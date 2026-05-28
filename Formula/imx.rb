class Imx < Formula
  desc "Standalone Rust image tool for ImageMagick-compatible slices"
  homepage "https://github.com/jskoiz/imx"
  license "ImageMagick"

  on_linux do
    on_intel do
      url "https://github.com/jskoiz/imx/releases/download/v0.19.0/imx-preview-0.19.0-x86_64-unknown-linux-gnu.tar.gz"
      sha256 "bdb0e3838cd006dde3bb36b2210eaa28404319e4f21aab83a0ad128d7e53fbc0"
    end

    on_arm do
      url "https://github.com/jskoiz/imx/releases/download/v0.19.0/imx-preview-0.19.0-aarch64-unknown-linux-gnu.tar.gz"
      sha256 "84f1d2a76dc5dd6a12f4c3e106255d9277a318d702c3463fdfcea55e1f389271"
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
    system bin/"imx", "self-test"
    require "json"
    identify_json = JSON.parse(shell_output("#{bin/"imx"} identify --json PPM:input.ppm"))
    assert_equal 1, identify_json.fetch("schema_version")
    assert_equal "PPM", identify_json.fetch("format")
    assert_equal 2, identify_json.fetch("width")
    assert_equal 1, identify_json.fetch("height")
    assert_equal "RGB", identify_json.fetch("channels")
    assert_equal 8, identify_json.fetch("depth")
    report_json = JSON.parse(shell_output("#{bin/"imx"} report --json PPM:input.ppm"))
    assert_equal "supported", report_json.fetch("status")
    assert_nil report_json.fetch("diagnostic_code")
    assert_equal "PPM", report_json.fetch("format")
    unsupported_report = JSON.parse(shell_output("#{bin/"imx"} report --json GIF:input.ppm"))
    assert_equal "unsupported", unsupported_report.fetch("status")
    assert_equal "input.unsupported_format_prefix", unsupported_report.fetch("diagnostic_code")
    mismatch_report = JSON.parse(shell_output("#{bin/"imx"} report --json QOI:input.ppm"))
    assert_equal "unsupported", mismatch_report.fetch("status")
    assert_equal "input.format_prefix_mismatch", mismatch_report.fetch("diagnostic_code")
    identify_error = JSON.parse(shell_output("#{bin/"imx"} identify --json QOI:input.ppm 2>&1", 1))
    assert_equal "unsupported", identify_error.fetch("status")
    assert_equal "input.format_prefix_mismatch", identify_error.fetch("diagnostic_code")
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
    progressive_hex = "ffd8ffe000104a46494600010100000100010000ffdb004300030202020202030202020303030304060404040404080606050609080a0a090809090a0c0f0c0a0b0e0b09090d110d0e0f101011100a0c12131210130f101010" \
      "ffdb00430103030304030408040408100b090b1010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010101010ffc20011080003000403011100021101031101" \
      "ffc40014000100000000000000000000000000000006ffc4001501010100000000000000000000000000000205ffda000c030100021003100000011d347fffc4001510010100000000000000000000000000000503" \
      "ffda000801010001050265140ca7ffc4001f1100020005050000000000000000000000010200030531411112131421ffda0008010301013f01a5d427f5f9491ba616763a0f59c96636c936b0c47f" \
      "ffc4001f1100020005050000000000000000000000010200041112210305142271ffda0008010201013f01e34b6e88af39a28c56e03a2e05ec683181524fa498ffc4001c1000030002030100000000000000000000010203041100058191" \
      "ffda0008010100063f02c75ebb36f8cb680a389d0a82db2bbf8aa3ce7fffc400161001010100000000000000000000000000011100ffda0008010100013f2111a3b847819763ffda000c030100020003000000103f" \
      "ffc4001811010100030000000000000000000000000111002131ffda0008010301013f104d4241dd88295313800033ffc4001811010100030000000000000000000000000121001131ffda0008010201013f106ca63d7160487003d0573f" \
      "ffc400161001010100000000000000000000000000011121ffda0008010100013f1066307afe986b00a05ad5ffd9"
    File.binwrite("progressive-rgb.jpg", [progressive_hex].pack("H*"))
    assert_match "format=JPEG width=4 height=3 channels=RGB depth=8", shell_output("#{bin/"imx"} identify JPEG:progressive-rgb.jpg")
    system bin/"imx", "JPEG:progressive-rgb.jpg", "PPM:progressive-rgb.ppm"
    assert_match "format=PPM width=4 height=3 channels=RGB depth=8", shell_output("#{bin/"imx"} identify PPM:progressive-rgb.ppm")
    progressive = File.binread("progressive-rgb.jpg")
    File.binwrite("progressive-o6.jpg", progressive.byteslice(0, 2) + segment + progressive.byteslice(2, progressive.bytesize - 2))
    assert_match "format=JPEG width=3 height=4 channels=RGB depth=8", shell_output("#{bin/"imx"} identify JPEG:progressive-o6.jpg")
    system bin/"imx", "JPEG:progressive-o6.jpg", "PPM:progressive-o6.ppm"
    assert_match "format=PPM width=3 height=4 channels=RGB depth=8", shell_output("#{bin/"imx"} identify PPM:progressive-o6.ppm")
    (testpath/"intake-comments.ppm").write "P3\n# v0.12 intake fixture\n2 1\n1023\n0 512 1023\n1023 256 128\n"
    (testpath/"intake-pgm16.pgm").write "P5\n2 1\n65535\n\x12\x34\xff\xff".b
    assert_match "format=PPM width=2 height=1 channels=RGB depth=16", shell_output("#{bin/"imx"} identify PPM:intake-comments.ppm")
    assert_match "format=PGM width=2 height=1 channels=GRAY depth=16", shell_output("#{bin/"imx"} identify PGM:intake-pgm16.pgm")
    system bin/"imx", "PPM:intake-comments.ppm", "PGM:intake-comments.pgm"
    system bin/"imx", "PGM:intake-pgm16.pgm", "FARBFELD:intake-pgm16.ff"
    assert_match "format=FARBFELD width=2 height=1 channels=RGBA depth=16", shell_output("#{bin/"imx"} identify FARBFELD:intake-pgm16.ff")
    system bin/"imx", "resize", "1x1", "PPM:input.ppm", "PPM:resized.ppm"
    assert_match "format=PPM width=1 height=1 channels=RGB depth=8", shell_output("#{bin/"imx"} identify PPM:resized.ppm")
    system bin/"imx", "resize-fit", "5x5", "PPM:input.ppm", "PPM:fit.ppm"
    assert_match "format=PPM width=5 height=3 channels=RGB depth=8", shell_output("#{bin/"imx"} identify PPM:fit.ppm")
    mkdir "batch"
    (testpath/"batch-ppm.ppm").write "P3\n2 1\n255\n255 0 0 0 0 255\n"
    (testpath/"batch-pgm.pgm").write "P2\n2 1\n255\n0 255\n"
    system bin/"imx", "batch-convert", "--to", "PPM", "--output-dir", "batch", "--resize-fit", "5x5", "PPM:batch-ppm.ppm", "PGM:batch-pgm.pgm"
    assert_match "format=PPM width=5 height=3 channels=RGB depth=8", shell_output("#{bin/"imx"} identify PPM:batch/batch-ppm.ppm")
    assert_match "format=PPM width=5 height=3 channels=RGB depth=8", shell_output("#{bin/"imx"} identify PPM:batch/batch-pgm.ppm")
    system bin/"imx", "input.ppm", "output.bmp"
    assert_match "format=BMP width=2 height=1 channels=RGB depth=8", shell_output("#{bin/"imx"} identify BMP:output.bmp")
    system bin/"imx", "BMP:output.bmp", "PPM:bmp-output.ppm"
    assert_match "format=PPM width=2 height=1 channels=RGB depth=8", shell_output("#{bin/"imx"} identify PPM:bmp-output.ppm")
    system bin/"imx", "resize", "1x1", "BMP:output.bmp", "BMP:resized.bmp"
    assert_match "format=BMP width=1 height=1 channels=RGB depth=8", shell_output("#{bin/"imx"} identify BMP:resized.bmp")
    system bin/"imx", "resize-fit", "5x5", "BMP:output.bmp", "BMP:fit.bmp"
    assert_match "format=BMP width=5 height=3 channels=RGB depth=8", shell_output("#{bin/"imx"} identify BMP:fit.bmp")
    mkdir "batch-bmp"
    system bin/"imx", "batch-convert", "--to", "BMP", "--output-dir", "batch-bmp", "--resize-fit", "5x5", "PPM:input.ppm"
    assert_match "format=BMP width=5 height=3 channels=RGB depth=8", shell_output("#{bin/"imx"} identify BMP:batch-bmp/input.bmp")
    system bin/"imx", "BMP:output.bmp", "BMP:rewrite.bmp"
    assert_match "format=BMP width=2 height=1 channels=RGB depth=8", shell_output("#{bin/"imx"} identify rewrite.bmp")
    system bin/"imx", "JPEG:output.jpg", "FARBFELD:jpeg-output.ff"
    assert_match "format=FARBFELD width=2 height=1 channels=RGBA depth=16", shell_output("#{bin/"imx"} identify FARBFELD:jpeg-output.ff")
    system bin/"imx", "JPEG:output.jpg", "JPEG:rewrite.jpg"
    assert_match "format=JPEG width=2 height=1 channels=RGB depth=8", shell_output("#{bin/"imx"} identify rewrite.jpg")
    system bin/"imx", "input.ppm", "rewrite.ppm"
    assert_match "format=PPM width=2 height=1 channels=RGB depth=8", shell_output("#{bin/"imx"} identify rewrite.ppm")
  end
end

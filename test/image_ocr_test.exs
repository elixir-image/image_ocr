defmodule ImageOcrTest do
  use ExUnit.Case, async: true

  import ImageOcr.TestFixtures

  describe "tesseract_version/0" do
    test "returns a 5.x version string" do
      version = ImageOcr.tesseract_version()
      assert is_binary(version)
      assert String.starts_with?(version, "5.")
    end
  end

  describe "new/1" do
    test "creates an instance with default options (ISO 639-1)" do
      assert {:ok, ocr} = ImageOcr.new()
      assert ocr.language == "en"
      assert ocr.tesseract_language == "eng"
      assert ocr.psm == :auto
      assert is_reference(ocr.ref)
    end

    test "accepts an ISO 639-1 atom" do
      assert {:ok, ocr} = ImageOcr.new(language: :en)
      assert ocr.language == "en"
      assert ocr.tesseract_language == "eng"
    end

    test "passes through Tesseract codes verbatim" do
      assert {:ok, ocr} = ImageOcr.new(language: "eng")
      assert ocr.language == "eng"
      assert ocr.tesseract_language == "eng"
    end

    test "rejects unknown ISO 639-1 codes" do
      assert_raise ArgumentError, ~r/unknown ISO 639-1/, fn ->
        ImageOcr.new(language: "qq")
      end
    end

    test "rejects ambiguous zh" do
      assert_raise ArgumentError, ~r/ambiguous/, fn ->
        ImageOcr.new(language: "zh")
      end
    end

    test "errors on missing trained-data" do
      assert {:error, {:missing_traineddata, ["fra"], _}} = ImageOcr.new(language: "fr")
    end

    test "errors on invalid psm" do
      assert_raise ArgumentError, fn -> ImageOcr.new(psm: :nonsense) end
    end

    test "applies SetVariable tweakables" do
      assert {:ok, _} = ImageOcr.new(variables: [tessedit_char_whitelist: "0123456789"])
    end

    test "rejects unknown variables" do
      assert {:error, :unknown_variable} =
               ImageOcr.new(variables: [definitely_not_a_real_variable: "x"])
    end
  end

  describe "read_text/3" do
    setup do
      {:ok, ocr} = ImageOcr.new()
      %{ocr: ocr}
    end

    test "recognises text from a Vix.Vips.Image", %{ocr: ocr} do
      image = text_image("Hello, Tesseract!")
      assert {:ok, "Hello, Tesseract!"} = ImageOcr.read_text(ocr, image)
    end

    test "recognises text from a file path", %{ocr: ocr} do
      path = text_image_file("Hello from disk")
      on_exit(fn -> File.rm(path) end)

      assert {:ok, text} = ImageOcr.read_text(ocr, path)
      assert text =~ "Hello from disk"
    end

    test "recognises text from in-memory PNG bytes", %{ocr: ocr} do
      bytes = text_image_png_bytes("In memory binary")
      assert {:ok, text} = ImageOcr.read_text(ocr, bytes)
      assert text =~ "In memory"
    end

    test "rejects unsupported input", %{ocr: ocr} do
      assert {:error, {:unsupported_input, _}} = ImageOcr.read_text(ocr, 42)
    end
  end

  describe "quick_read/2" do
    test "performs OCR without explicitly building an instance" do
      image = text_image("One shot")
      assert {:ok, text} = ImageOcr.quick_read(image)
      assert text =~ "One shot"
    end
  end

  describe "recognize/3" do
    test "returns per-word results with confidence and bbox" do
      {:ok, ocr} = ImageOcr.new()
      image = text_image("Foo Bar")

      assert {:ok, words} = ImageOcr.recognize(ocr, image)
      assert is_list(words)
      assert length(words) >= 2

      Enum.each(words, fn word ->
        assert is_binary(word.text)
        assert is_float(word.confidence)
        assert match?({_, _, _, _}, word.bbox)
      end)

      texts = Enum.map(words, & &1.text)
      assert Enum.any?(texts, &(&1 =~ "Foo"))
      assert Enum.any?(texts, &(&1 =~ "Bar"))
    end
  end
end

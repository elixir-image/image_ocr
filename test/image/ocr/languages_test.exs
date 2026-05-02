defmodule Image.OCR.LanguagesTest do
  use ExUnit.Case, async: true

  doctest Image.OCR.Languages

  alias Image.OCR.Languages

  describe "to_tesseract/1" do
    test "translates ISO 639-1 strings" do
      assert Languages.to_tesseract("en") == "eng"
      assert Languages.to_tesseract("fr") == "fra"
      assert Languages.to_tesseract("de") == "deu"
      assert Languages.to_tesseract("ja") == "jpn"
    end

    test "translates ISO 639-1 atoms" do
      assert Languages.to_tesseract(:en) == "eng"
      assert Languages.to_tesseract(:fr) == "fra"
    end

    test "translates BCP-47 region/script tags" do
      assert Languages.to_tesseract("zh-Hans") == "chi_sim"
      assert Languages.to_tesseract("zh-Hant") == "chi_tra"
      assert Languages.to_tesseract("zh-CN") == "chi_sim"
      assert Languages.to_tesseract("zh-TW") == "chi_tra"
      assert Languages.to_tesseract("sr-Latn") == "srp_latn"
      assert Languages.to_tesseract("sr-Cyrl") == "srp"
    end

    test "passes Tesseract codes through unchanged" do
      assert Languages.to_tesseract("eng") == "eng"
      assert Languages.to_tesseract("chi_sim") == "chi_sim"
      assert Languages.to_tesseract("frk") == "frk"
      assert Languages.to_tesseract("osd") == "osd"
    end

    test "translates +-joined compound codes" do
      assert Languages.to_tesseract("en+fr") == "eng+fra"
      assert Languages.to_tesseract("zh-Hans+en") == "chi_sim+eng"
      assert Languages.to_tesseract("eng+frk") == "eng+frk"
    end

    test "rejects ambiguous zh" do
      assert_raise ArgumentError, ~r/ambiguous.*zh/, fn ->
        Languages.to_tesseract("zh")
      end
    end

    test "rejects unknown ISO 639-1 codes" do
      assert_raise ArgumentError, ~r/unknown ISO 639-1/, fn ->
        Languages.to_tesseract("qq")
      end
    end

    test "rejects parseable BCP-47 tags with no Tesseract mapping" do
      assert_raise ArgumentError, ~r/no Tesseract trained-data mapping/, fn ->
        Languages.to_tesseract("qq-XX")
      end
    end
  end

  describe "to_tesseract/1 with Localize" do
    @describetag :localize

    setup do
      unless Languages.localize_available?() do
        flunk("Localize must be loaded for these tests")
      end

      :ok
    end

    test "parses BCP-47 with territory subtag" do
      assert Languages.to_tesseract("en-US") == "eng"
      assert Languages.to_tesseract("fr-CA") == "fra"
      assert Languages.to_tesseract("pt-BR") == "por"
    end

    test "parses BCP-47 with script + territory" do
      assert Languages.to_tesseract("zh-Hans-CN") == "chi_sim"
      assert Languages.to_tesseract("zh-Hant-TW") == "chi_tra"
      assert Languages.to_tesseract("sr-Latn-RS") == "srp_latn"
      assert Languages.to_tesseract("sr-Cyrl-RS") == "srp"
    end

    test "rejects ambiguous zh-* without script" do
      assert_raise ArgumentError, ~r/ambiguous Chinese/, fn ->
        # zh-XX with an unknown territory has no script subtag and Localize
        # doesn't add likely subtags by default.
        Languages.to_tesseract("zh-x-private")
      end
    end
  end

  describe "from_tesseract/1" do
    test "returns ISO 639-1 when known" do
      assert Languages.from_tesseract("eng") == "en"
      assert Languages.from_tesseract("fra") == "fr"
      assert Languages.from_tesseract("jpn") == "ja"
    end

    test "passes unknown codes through unchanged" do
      assert Languages.from_tesseract("frk") == "frk"
      assert Languages.from_tesseract("chi_sim") == "chi_sim"
      assert Languages.from_tesseract("osd") == "osd"
    end
  end
end

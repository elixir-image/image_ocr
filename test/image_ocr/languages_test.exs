defmodule ImageOcr.LanguagesTest do
  use ExUnit.Case, async: true

  doctest ImageOcr.Languages

  alias ImageOcr.Languages

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

    test "rejects unknown BCP-47 tags" do
      assert_raise ArgumentError, ~r/unknown BCP-47/, fn ->
        Languages.to_tesseract("xx-Hans")
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

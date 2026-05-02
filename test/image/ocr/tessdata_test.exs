defmodule Image.OCR.TessdataTest do
  # async: false because these tests mutate Application env / OS env
  # (`:image_ocr, :tessdata_path` and `TESSDATA_PREFIX`), which is global
  # state that would otherwise race Image.OCR.new/1 calls in other modules.
  use ExUnit.Case, async: false

  alias Image.OCR.Tessdata

  describe "datapath/1" do
    test "explicit option wins" do
      assert Tessdata.datapath(datapath: "/tmp/foo") == "/tmp/foo"
    end

    test "falls back to vendored priv path when nothing is configured" do
      Application.delete_env(:image_ocr, :tessdata_path)
      System.delete_env("TESSDATA_PREFIX")
      assert String.ends_with?(Tessdata.datapath(), "priv/tessdata")
    end

    test "honours :image_ocr application config" do
      Application.put_env(:image_ocr, :tessdata_path, "/tmp/from-config")
      on_exit(fn -> Application.delete_env(:image_ocr, :tessdata_path) end)
      assert Tessdata.datapath() == "/tmp/from-config"
    end
  end

  describe "installed_languages/1" do
    test "lists vendored languages" do
      assert "eng" in Tessdata.installed_languages()
    end

    test "returns [] for a missing directory" do
      assert Tessdata.installed_languages(datapath: "/nonexistent/path/here") == []
    end
  end

  describe "installed?/2" do
    test "true for vendored eng" do
      assert Tessdata.installed?("eng")
    end

    test "false for an unknown language" do
      refute Tessdata.installed?("zzz")
    end
  end
end

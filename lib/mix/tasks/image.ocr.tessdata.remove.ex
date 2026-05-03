defmodule Mix.Tasks.Image.Ocr.Tessdata.Remove do
  @shortdoc "Remove an installed Tesseract trained-data file"

  @moduledoc """
  Deletes one or more `<language>.traineddata` files and their manifest
  entries.

  ## Usage

      mix image.ocr.tessdata.remove LANG [LANG ...] [--path DIR]

  Languages can be specified using the same identifiers accepted by
  `mix image.ocr.tessdata.add` (ISO 639-1, BCP-47, or Tesseract codes).
  """

  use Mix.Task

  alias Image.OCR.{Languages, Tessdata}
  alias Image.OCR.Tessdata.Manifest

  @switches [path: :string]

  @impl Mix.Task
  def run(args) do
    {opts, langs, _} = OptionParser.parse(args, switches: @switches)

    if langs == [] do
      Mix.raise("usage: mix image.ocr.tessdata.remove LANG [LANG ...]")
    end

    Mix.Task.run("app.config")
    dest = opts[:path] || Tessdata.datapath()

    Enum.each(langs, fn lang ->
      tess_code = Languages.to_tesseract(lang)
      file = Path.join(dest, tess_code <> ".traineddata")
      label = if lang == tess_code, do: lang, else: "#{lang} (#{tess_code})"

      case File.rm(file) do
        :ok ->
          Manifest.delete(dest, tess_code)
          Mix.shell().info("  ✓ removed #{label}")

        {:error, :enoent} ->
          Mix.shell().info("  · #{label} not present")

        {:error, reason} ->
          Mix.shell().error("  ✗ #{label}: #{inspect(reason)}")
      end
    end)
  end
end

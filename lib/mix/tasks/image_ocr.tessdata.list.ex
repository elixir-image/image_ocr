defmodule Mix.Tasks.ImageOcr.Tessdata.List do
  @shortdoc "List installed Tesseract trained-data files"

  @moduledoc """
  Lists every `<language>.traineddata` file in the resolved trained-data
  directory along with provenance from the manifest.

  ## Usage

      mix image_ocr.tessdata.list [--path DIR]
  """

  use Mix.Task

  alias ImageOcr.{Languages, Tessdata}
  alias ImageOcr.Tessdata.Manifest

  @switches [path: :string]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches)
    Mix.Task.run("app.config")
    dest = opts[:path] || Tessdata.datapath()

    Mix.shell().info("Trained-data directory: #{dest}")

    languages = Tessdata.installed_languages(datapath: dest)

    if languages == [] do
      Mix.shell().info("(no trained-data files found)")
    else
      manifest = Manifest.read(dest)

      Enum.each(languages, fn lang ->
        iso = Languages.from_tesseract(lang)
        label = if iso == lang, do: lang, else: "#{iso} (#{lang})"

        case Map.get(manifest, lang) do
          nil ->
            Mix.shell().info("  #{label}  (no manifest entry)")

          entry ->
            Mix.shell().info(
              "  #{label}  variant=#{entry.variant} branch=#{entry.branch} " <>
                "size=#{entry.size}B sha256=#{String.slice(entry.sha256, 0, 12)}… " <>
                "fetched=#{entry.fetched_at}"
            )
        end
      end)
    end
  end
end

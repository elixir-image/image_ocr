defmodule Mix.Tasks.Image.Ocr.Tessdata.Update do
  @shortdoc "Refresh every installed Tesseract trained-data file"

  @moduledoc """
  Re-fetches every trained-data file recorded in the manifest, picking up the
  latest commit on each language's recorded branch.

  ## Usage

      mix image.ocr.tessdata.update [--path DIR]

  ### Options

    * `--path` — Directory to refresh. Defaults to the value resolved by
      `Image.OCR.Tessdata.datapath/0`.
  """

  use Mix.Task

  alias Image.OCR.Tessdata
  alias Image.OCR.Tessdata.{Fetcher, Manifest}

  @switches [path: :string]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} = OptionParser.parse(args, switches: @switches)
    Mix.Task.run("app.config")
    dest = opts[:path] || Tessdata.datapath()
    manifest = Manifest.read(dest)

    if manifest == %{} do
      Mix.shell().info("No trained-data installed at #{dest}; nothing to update.")
    else
      Mix.shell().info("Refreshing trained-data in #{dest}")

      Enum.each(manifest, fn {lang, entry} ->
        case Fetcher.fetch(lang, dest, variant: entry.variant, branch: entry.branch) do
          {:ok, info} ->
            Manifest.upsert(dest, lang, %{
              variant: entry.variant,
              branch: entry.branch,
              sha256: info.sha256,
              size: info.size,
              fetched_at: DateTime.utc_now() |> DateTime.to_iso8601()
            })

            changed? = info.sha256 != entry.sha256
            tag = if changed?, do: "updated", else: "unchanged"
            Mix.shell().info("  ✓ #{lang} (#{tag})")

          {:error, reason} ->
            Mix.shell().error("  ✗ #{lang}: #{inspect(reason)}")
        end
      end)
    end
  end
end

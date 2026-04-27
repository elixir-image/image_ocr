defmodule Mix.Tasks.ImageOcr.Tessdata.Add do
  @shortdoc "Download a Tesseract trained-data file for one or more languages"

  @moduledoc """
  Downloads `<language>.traineddata` from the upstream `tessdata_*` GitHub
  repository into the configured trained-data directory.

  ## Usage

      mix image_ocr.tessdata.add LANG [LANG ...] [--variant fast|best|legacy]
                                                 [--branch BRANCH]
                                                 [--path DIR]
                                                 [--source URL]
                                                 [--force]

  Languages are specified using ISO 639-1 codes (`en`, `fr`, `de`), BCP-47
  tags for region/script-specific variants (`zh-Hans`, `zh-Hant`,
  `sr-Latn`), or Tesseract codes verbatim where ISO 639-1 cannot express
  the language (`frk`, `osd`). See `ImageOcr.Languages`.

  ### Options

    * `--variant`  — Trained-data variant. One of `fast` (smallest, fastest;
                     ~2-4 MB per language), `best` (most accurate; ~10-15 MB),
                     or `legacy` (legacy + LSTM combined; largest). Defaults
                     to the `:image_ocr, :default_variant` application config,
                     or `fast` if unset.

                     To install the larger / more accurate English data:

                         mix image_ocr.tessdata.add en --variant best

    * `--branch`   — Upstream git branch to fetch from. Defaults to `main`.

    * `--path`     — Destination directory. Defaults to the value resolved by
                     `ImageOcr.Tessdata.datapath/0` (which honours the
                     `:image_ocr, :tessdata_path` application config and the
                     `TESSDATA_PREFIX` environment variable).

    * `--source`   — Explicit URL to fetch from. Useful for mirrors. Only
                     valid when adding a single language.

    * `--force`    — Overwrite an existing trained-data file even when its
                     SHA matches the previous fetch.

  ## Examples

      mix image_ocr.tessdata.add en
      mix image_ocr.tessdata.add fr de --variant best
      mix image_ocr.tessdata.add zh-Hans --path /var/lib/tessdata
      mix image_ocr.tessdata.add ja zh-Hant ko
  """

  use Mix.Task

  alias ImageOcr.{Languages, Tessdata}
  alias ImageOcr.Tessdata.{Fetcher, Manifest}

  @switches [
    variant: :string,
    branch: :string,
    path: :string,
    source: :string,
    force: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    {opts, langs, _} = OptionParser.parse(args, switches: @switches)

    if langs == [] do
      Mix.raise("usage: mix image_ocr.tessdata.add LANG [LANG ...]")
    end

    if opts[:source] && length(langs) > 1 do
      Mix.raise("--source can only be used when adding a single language")
    end

    Mix.Task.run("app.config")

    dest = opts[:path] || Tessdata.datapath()

    variant =
      opts[:variant] || Application.get_env(:image_ocr, :default_variant, "fast")

    branch = opts[:branch] || "main"

    unless variant in Fetcher.variants() do
      Mix.raise(
        "invalid --variant #{inspect(variant)}; expected one of #{inspect(Fetcher.variants())}"
      )
    end

    Mix.shell().info("Writing trained-data to #{dest}")

    Enum.each(langs, fn lang ->
      fetch_one(lang, dest, variant, branch, opts)
    end)
  end

  defp fetch_one(lang, dest, variant, branch, opts) do
    tess_code = Languages.to_tesseract(lang)
    fetch_options = [variant: variant, branch: branch, source: opts[:source]]

    case Fetcher.fetch(tess_code, dest, fetch_options) do
      {:ok, info} ->
        Manifest.upsert(dest, tess_code, %{
          user_code: lang,
          variant: variant,
          branch: branch,
          sha256: info.sha256,
          size: info.size,
          fetched_at: DateTime.utc_now() |> DateTime.to_iso8601()
        })

        label = if lang == tess_code, do: lang, else: "#{lang} → #{tess_code}"

        Mix.shell().info(
          "  ✓ #{label} [#{variant}] (#{format_bytes(info.size)}, sha256:#{String.slice(info.sha256, 0, 12)}…)"
        )

      {:error, reason} ->
        Mix.raise("failed to fetch #{lang}: #{inspect(reason)}")
    end
  end

  defp format_bytes(n) when n >= 1_048_576, do: "#{Float.round(n / 1_048_576, 2)} MB"
  defp format_bytes(n) when n >= 1024, do: "#{Float.round(n / 1024, 1)} KB"
  defp format_bytes(n), do: "#{n} B"
end

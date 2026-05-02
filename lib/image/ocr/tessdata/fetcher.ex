defmodule Image.OCR.Tessdata.Fetcher do
  @moduledoc false

  @repos %{
    "fast" => "tessdata_fast",
    "best" => "tessdata_best",
    "legacy" => "tessdata"
  }

  @default_branch "main"

  @doc """
  Downloads a single language's trained-data file into `dest_dir`.

  Returns `{:ok, %{path: ..., sha256: ..., size: ..., source: ...}}` on
  success.
  """
  def fetch(language, dest_dir, options) do
    variant = Keyword.get(options, :variant, "fast")
    branch = Keyword.get(options, :branch, @default_branch)
    source = Keyword.get(options, :source) || default_source(variant, branch, language)

    File.mkdir_p!(dest_dir)
    dest_file = Path.join(dest_dir, language <> ".traineddata")

    with {:ok, body} <- http_get(source) do
      File.write!(dest_file, body)
      sha = :crypto.hash(:sha256, body) |> Base.encode16(case: :lower)
      {:ok, %{path: dest_file, sha256: sha, size: byte_size(body), source: source}}
    end
  end

  defp default_source(variant, branch, language) do
    repo = Map.fetch!(@repos, variant)

    "https://github.com/tesseract-ocr/#{repo}/raw/#{branch}/#{language}.traineddata"
  end

  defp http_get(url) do
    {:ok, _} = Application.ensure_all_started(:inets)
    {:ok, _} = Application.ensure_all_started(:ssl)

    request = {String.to_charlist(url), [{~c"user-agent", ~c"image_ocr-mix"}]}

    http_options = [
      autoredirect: true,
      timeout: 60_000,
      connect_timeout: 15_000,
      ssl: [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        depth: 5,
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ]
    ]

    options = [body_format: :binary]

    case :httpc.request(:get, request, http_options, options) do
      {:ok, {{_, 200, _}, _headers, body}} -> {:ok, body}
      {:ok, {{_, status, _}, _, _}} -> {:error, {:http_status, status}}
      {:error, reason} -> {:error, {:http_error, reason}}
    end
  end

  @doc false
  def variants, do: Map.keys(@repos)
end

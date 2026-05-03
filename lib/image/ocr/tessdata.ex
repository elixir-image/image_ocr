defmodule Image.OCR.Tessdata do
  @moduledoc """
  Helpers for resolving and managing Tesseract trained-data (`tessdata`) files.

  Trained-data files (`<lang>.traineddata`) live in a directory that Tesseract
  reads at initialisation time. `Image.OCR` resolves that directory in the
  following order:

  1. The `:datapath` option passed to `Image.OCR.new/1`.

  2. The `:tessdata_path` application environment value:

         config :image_ocr, tessdata_path: "/var/lib/image_ocr/tessdata"

  3. The `TESSDATA_PREFIX` operating-system environment variable.

  4. The vendored fallback at `priv/tessdata/` inside the `:image_ocr` package.

  See `Mix.Tasks.Image.Ocr.Tessdata.Add` and friends for managing the contents
  of a configured directory.

  """

  @vendored_subdir "tessdata"

  @doc """
  Returns the absolute path to the directory in which trained-data files are
  read from and written to.

  ### Arguments

  * `options` is an optional keyword list. See the options below.

  ### Options

  * `:datapath` is an explicit path that overrides every other lookup. When
    `nil` (the default) the standard resolution order is used.

  ### Returns

  * A string containing the absolute path to the trained-data directory.

  ### Examples

      iex> path = Image.OCR.Tessdata.datapath()
      iex> File.dir?(path)
      true

  """
  @spec datapath(keyword()) :: String.t()
  def datapath(options \\ []) do
    case Keyword.get(options, :datapath) do
      nil -> resolve_datapath()
      explicit -> Path.expand(explicit)
    end
  end

  defp resolve_datapath do
    cond do
      configured = Application.get_env(:image_ocr, :tessdata_path) ->
        Path.expand(configured)

      env = System.get_env("TESSDATA_PREFIX") ->
        Path.expand(env)

      true ->
        vendored_path()
    end
  end

  @doc """
  Returns the absolute path to the directory of trained-data shipped with the
  `image_ocr` package.

  ### Returns

  * A string containing the absolute path to the vendored trained-data
    directory.

  ### Examples

      iex> Image.OCR.Tessdata.vendored_path() |> String.ends_with?("priv/tessdata")
      true

  """
  @spec vendored_path() :: String.t()
  def vendored_path do
    :code.priv_dir(:image_ocr)
    |> List.to_string()
    |> Path.join(@vendored_subdir)
  end

  @doc """
  Returns the list of language codes installed in the resolved trained-data
  directory.

  ### Arguments

  * `options` is an optional keyword list. See `datapath/1` for the supported
    options.

  ### Returns

  * A list of language code strings (for example `["eng", "fra"]`) sorted
    alphabetically. Returns `[]` when the directory does not exist.

  ### Examples

      iex> "eng" in Image.OCR.Tessdata.installed_languages()
      true

  """
  @spec installed_languages(keyword()) :: [String.t()]
  def installed_languages(options \\ []) do
    path = datapath(options)

    case File.ls(path) do
      {:ok, entries} ->
        entries
        |> Enum.filter(&String.ends_with?(&1, ".traineddata"))
        |> Enum.map(&String.replace_suffix(&1, ".traineddata", ""))
        |> Enum.sort()

      {:error, _} ->
        []
    end
  end

  @doc """
  Returns the absolute path to the trained-data file for `language` inside the
  resolved trained-data directory.

  ### Arguments

  * `language` is a language code string such as `"eng"` or `"fra"`.

  * `options` is an optional keyword list. See `datapath/1` for the supported
    options.

  ### Returns

  * A string containing the absolute path. The file is not guaranteed to
    exist.

  """
  @spec language_file(String.t(), keyword()) :: String.t()
  def language_file(language, options \\ []) when is_binary(language) do
    Path.join(datapath(options), language <> ".traineddata")
  end

  @doc """
  Returns `true` when `language` has a trained-data file in the resolved
  trained-data directory.

  """
  @spec installed?(String.t(), keyword()) :: boolean()
  def installed?(language, options \\ []) do
    language |> language_file(options) |> File.exists?()
  end
end

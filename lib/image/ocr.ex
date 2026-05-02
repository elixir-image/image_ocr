defmodule Image.OCR do
  @moduledoc """
  Idiomatic Elixir interface to the [Tesseract](https://github.com/tesseract-ocr/tesseract)
  OCR engine.

  `Image.OCR` is a thin NIF binding (Tesseract 5.x) that accepts images as
  `Vix.Vips.Image` structs, file paths, or in-memory image binaries and
  returns recognised text.

  ## Quick start

      {:ok, instance} = Image.OCR.new()
      {:ok, text}     = Image.OCR.read_text(instance, "page.png")

  Or, in one shot:

      {:ok, text} = Image.OCR.read_text("page.png")

  ## Concurrency

  A single `Image.OCR` instance wraps one `tesseract::TessBaseAPI`, which is
  not safe for concurrent use. Calls on a shared instance are serialised
  through a per-instance mutex; for true parallelism, build one instance per
  worker — the simplest way is `Image.OCR.Pool`.

  ## Trained-data

  `Image.OCR` ships with English (`eng`) trained-data. To install additional
  languages, see `Mix.Tasks.Image.OCR.Tessdata.Add`. The trained-data location
  is resolved by `Image.OCR.Tessdata.datapath/1`.

  """

  alias Image.OCR.{Input, Languages, Nif, Tessdata}

  @enforce_keys [:ref, :locale, :tesseract_language]
  defstruct [:ref, :locale, :tesseract_language, :datapath, :psm]

  @typedoc """
  An OCR instance — wraps a single Tesseract API resource.

  * `:locale` — the user-facing locale identifier as supplied to `new/1`
    (e.g. `"en"`, `"en-US"`, `"zh-Hans-CN"`).

  * `:tesseract_language` — the resolved Tesseract trained-data code that
    was passed to `TessBaseAPI::Init` (e.g. `"eng"`).
  """
  @type t :: %__MODULE__{
          ref: reference() | binary(),
          locale: String.t(),
          tesseract_language: String.t(),
          datapath: String.t() | nil,
          psm: psm()
        }

  @typedoc """
  A page-segmentation mode. See `psm/0` for valid values.
  """
  @type psm ::
          :osd_only
          | :auto_osd
          | :auto_only
          | :auto
          | :single_column
          | :single_block_vert_text
          | :single_block
          | :single_line
          | :single_word
          | :circle_word
          | :single_char
          | :sparse_text
          | :sparse_text_osd
          | :raw_line

  @typedoc """
  A recognised word together with its confidence and bounding box.
  """
  @type word_result :: %{
          text: String.t(),
          confidence: float(),
          bbox: {non_neg_integer(), non_neg_integer(), non_neg_integer(), non_neg_integer()}
        }

  @psm_map %{
    osd_only: 0,
    auto_osd: 1,
    auto_only: 2,
    auto: 3,
    single_column: 4,
    single_block_vert_text: 5,
    single_block: 6,
    single_line: 7,
    single_word: 8,
    circle_word: 9,
    single_char: 10,
    sparse_text: 11,
    sparse_text_osd: 12,
    raw_line: 13
  }

  @doc """
  Builds a new OCR instance.

  ### Arguments

  * `options` is an optional keyword list. See the options below.

  ### Options

  * `:locale` is the locale identifier. Accepts ISO 639-1 codes (`"en"`,
    `:en`, `"fr"`), BCP-47 tags for region/script variants (`"en-US"`,
    `"zh-Hans"`, `"sr-Latn"`), Tesseract codes verbatim (`"frk"`, `"osd"`),
    or `+`-joined combinations (`"en+fr"`, `"chi_sim+eng"`). Defaults to
    `"en"`. Full BCP-47 parsing requires the optional `:localize`
    dependency. See `Image.OCR.Languages`.

  * `:datapath` is the directory containing `<language>.traineddata` files.
    Defaults to the value resolved by `Image.OCR.Tessdata.datapath/1`.

  * `:psm` is the page-segmentation mode atom. Defaults to `:auto`. See
    `t:psm/0` for the full list.

  * `:variables` is a keyword list of `SetVariable/2` tweakables, applied
    after initialisation. Example: `[tessedit_char_whitelist: "0123456789"]`.

  ### Returns

  * `{:ok, %Image.OCR{}}` on success.

  * `{:error, reason}` if Tesseract initialisation fails (commonly because
    the trained-data file is missing).

  ### Examples

      iex> {:ok, ocr} = Image.OCR.new()
      iex> {ocr.locale, ocr.tesseract_language}
      {"en", "eng"}

  """
  @spec new(keyword()) :: {:ok, t()} | {:error, term()}
  def new(options \\ []) do
    locale = Keyword.get(options, :locale, "en") |> normalize_locale()
    tess_language = Languages.to_tesseract(locale)
    datapath = Tessdata.datapath(options)
    psm = Keyword.get(options, :psm, :auto)
    psm_int = Map.get(@psm_map, psm) || raise ArgumentError, "invalid :psm — #{inspect(psm)}"

    with :ok <- assert_languages_installed(tess_language, datapath),
         {:ok, ref} <- Nif.init_nif(tess_language, datapath, psm_int),
         :ok <- apply_variables(ref, Keyword.get(options, :variables, [])) do
      {:ok,
       %__MODULE__{
         ref: ref,
         locale: locale,
         tesseract_language: tess_language,
         datapath: datapath,
         psm: psm
       }}
    end
  end

  defp normalize_locale(code) when is_atom(code), do: Atom.to_string(code)
  defp normalize_locale(code) when is_binary(code), do: code

  @doc """
  Recognises text in `input` using `instance` and returns the result as a
  UTF-8 string.

  ### Arguments

  * `instance` is an `%Image.OCR{}` struct returned by `new/1`.

  * `input` is a `Vix.Vips.Image.t()`, a path to an image file, or a binary
    of encoded image data. See `Image.OCR.Input`.

  * `options` is reserved for future use.

  ### Returns

  * `{:ok, text}` on success, where `text` is the recognised UTF-8 string.

  * `{:error, reason}` on failure.

  ### Examples

      {:ok, ocr}  = Image.OCR.new()
      {:ok, text} = Image.OCR.read_text(ocr, "page.png")

      # Or with a Vix.Vips.Image already in memory:
      {:ok, image} = Vix.Vips.Image.new_from_file("page.png")
      {:ok, text}  = Image.OCR.read_text(ocr, image)

  """
  @spec read_text(t(), Input.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def read_text(%__MODULE__{ref: ref}, input, _options \\ []) do
    with {:ok, image} <- Input.to_vimage(input),
         {:ok, buf} <- Input.to_pixel_buffer(image),
         {:ok, text} <-
           Nif.recognize_nif(
             ref,
             buf.pixels,
             buf.width,
             buf.height,
             buf.bytes_per_pixel,
             buf.bytes_per_line
           ) do
      {:ok, String.trim_trailing(text)}
    end
  end

  @doc """
  One-shot convenience: builds a default instance, recognises `input`, and
  returns the recognised text.

  Equivalent to `with {:ok, ocr} <- new(options), do: read_text(ocr, input)`.
  Prefer `new/1` + `read_text/3` (or `Image.OCR.Pool`) when calling more than
  once — building a fresh Tesseract instance per call is expensive.

  ### Arguments

  * `input` is any value accepted by `read_text/3`.

  * `options` is forwarded to `new/1`.

  ### Returns

  * `{:ok, text}` on success.

  * `{:error, reason}` on failure.

  """
  @spec quick_read(Input.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def quick_read(input, options \\ []) do
    with {:ok, instance} <- new(options) do
      read_text(instance, input)
    end
  end

  @doc """
  Recognises `input` and returns each word with its confidence and bounding
  box.

  ### Arguments

  * `instance` is an `%Image.OCR{}` struct returned by `new/1`.

  * `input` is any value accepted by `read_text/3`.

  * `options` is reserved for future use.

  ### Returns

  * `{:ok, [word_result]}` where each entry is a map with `:text`,
    `:confidence` (0–100), and `:bbox` (`{x1, y1, x2, y2}`) keys.

  * `{:error, reason}` on failure.

  """
  @spec recognize(t(), Input.t(), keyword()) :: {:ok, [word_result()]} | {:error, term()}
  def recognize(%__MODULE__{ref: ref}, input, _options \\ []) do
    with {:ok, image} <- Input.to_vimage(input),
         {:ok, buf} <- Input.to_pixel_buffer(image) do
      Nif.recognize_with_boxes_nif(
        ref,
        buf.pixels,
        buf.width,
        buf.height,
        buf.bytes_per_pixel,
        buf.bytes_per_line
      )
    end
  end

  @doc """
  Returns the linked Tesseract library version as a string.

  ### Returns

  * A string such as `"5.5.1"`.

  """
  @spec tesseract_version() :: String.t()
  def tesseract_version, do: Nif.tesseract_version_nif()

  defp assert_languages_installed(language, datapath) do
    missing =
      language
      |> String.split("+", trim: true)
      |> Enum.reject(&File.exists?(Path.join(datapath, &1 <> ".traineddata")))

    case missing do
      [] -> :ok
      langs -> {:error, {:missing_traineddata, langs, datapath}}
    end
  end

  defp apply_variables(_ref, []), do: :ok

  defp apply_variables(ref, [{key, value} | rest]) do
    case Nif.set_variable_nif(ref, to_string(key), to_string(value)) do
      :ok -> apply_variables(ref, rest)
      error -> error
    end
  end
end

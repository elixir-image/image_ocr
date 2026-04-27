defmodule ImageOcr.Languages do
  @moduledoc """
  Translation between user-facing language identifiers and Tesseract's
  trained-data filename codes.

  All public `ImageOcr` and mix-task language arguments accept any of:

  * An ISO 639-1 two-letter code, as a string or atom: `"en"`, `:en`,
    `"fr"`, `:de`.

  * A BCP-47 tag for region- or script-specific variants where ISO 639-1
    alone is ambiguous: `"zh-Hans"`, `"zh-Hant"`, `"sr-Latn"`,
    `"az-Cyrl"`.

  * A Tesseract trained-data code passed through verbatim, for languages or
    artefacts ISO 639-1 cannot express: `"eng"`, `"chi_sim"`, `"frk"`
    (German Fraktur), `"osd"` (orientation/script detection),
    `"script/Latin"`.

  * A `+`-joined combination of any of the above: `"en+fr"`, `"chi_sim+eng"`.

  ## Ambiguous codes

  ISO 639-1 `zh` does not specify a script and is rejected — use `"zh-Hans"`
  for Simplified Chinese or `"zh-Hant"` for Traditional Chinese.

  """

  # Unambiguous ISO 639-1 → Tesseract code mappings.
  @iso639_1 %{
    "af" => "afr",
    "am" => "amh",
    "ar" => "ara",
    "as" => "asm",
    "az" => "aze",
    "be" => "bel",
    "bg" => "bul",
    "bn" => "ben",
    "bo" => "bod",
    "bs" => "bos",
    "ca" => "cat",
    "cs" => "ces",
    "cy" => "cym",
    "da" => "dan",
    "de" => "deu",
    "dz" => "dzo",
    "el" => "ell",
    "en" => "eng",
    "eo" => "epo",
    "es" => "spa",
    "et" => "est",
    "eu" => "eus",
    "fa" => "fas",
    "fi" => "fin",
    "fr" => "fra",
    "ga" => "gle",
    "gd" => "gla",
    "gl" => "glg",
    "gu" => "guj",
    "he" => "heb",
    "hi" => "hin",
    "hr" => "hrv",
    "hu" => "hun",
    "hy" => "hye",
    "id" => "ind",
    "is" => "isl",
    "it" => "ita",
    "iu" => "iku",
    "ja" => "jpn",
    "jv" => "jav",
    "ka" => "kat",
    "kk" => "kaz",
    "km" => "khm",
    "kn" => "kan",
    "ko" => "kor",
    "ku" => "kur",
    "ky" => "kir",
    "la" => "lat",
    "lo" => "lao",
    "lt" => "lit",
    "lv" => "lav",
    "mk" => "mkd",
    "ml" => "mal",
    "mn" => "mon",
    "mr" => "mar",
    "ms" => "msa",
    "mt" => "mlt",
    "my" => "mya",
    "ne" => "nep",
    "nl" => "nld",
    "no" => "nor",
    "or" => "ori",
    "pa" => "pan",
    "pl" => "pol",
    "ps" => "pus",
    "pt" => "por",
    "ro" => "ron",
    "ru" => "rus",
    "si" => "sin",
    "sk" => "slk",
    "sl" => "slv",
    "sq" => "sqi",
    "sr" => "srp",
    "sv" => "swe",
    "sw" => "swa",
    "ta" => "tam",
    "te" => "tel",
    "tg" => "tgk",
    "th" => "tha",
    "ti" => "tir",
    "tk" => "tuk",
    "tl" => "tgl",
    "tr" => "tur",
    "ug" => "uig",
    "uk" => "ukr",
    "ur" => "urd",
    "uz" => "uzb",
    "vi" => "vie",
    "yi" => "yid",
    "yo" => "yor"
  }

  # BCP-47 region/script tags for cases where ISO 639-1 alone is ambiguous.
  @bcp47 %{
    "zh-Hans" => "chi_sim",
    "zh-CN" => "chi_sim",
    "zh-Hant" => "chi_tra",
    "zh-TW" => "chi_tra",
    "zh-HK" => "chi_tra",
    "sr-Cyrl" => "srp",
    "sr-Latn" => "srp_latn",
    "az-Cyrl" => "aze_cyrl",
    "uz-Cyrl" => "uzb_cyrl"
  }

  @reverse for {k, v} <- @iso639_1, into: %{}, do: {v, k}

  @doc """
  Translates a user-supplied language identifier to the corresponding
  Tesseract trained-data code (the basename of the `.traineddata` file).

  Compound `+`-joined identifiers are translated component-wise.

  ### Arguments

  * `code` is a string or atom describing one or more languages. See the
    moduledoc for the accepted forms.

  ### Returns

  * The translated string, e.g. `"eng"`, `"chi_sim+eng"`, or `"frk"`.

  ### Examples

      iex> ImageOcr.Languages.to_tesseract(:en)
      "eng"

      iex> ImageOcr.Languages.to_tesseract("zh-Hans")
      "chi_sim"

      iex> ImageOcr.Languages.to_tesseract("en+fr")
      "eng+fra"

      iex> ImageOcr.Languages.to_tesseract("frk")
      "frk"

  """
  @spec to_tesseract(atom() | String.t()) :: String.t()
  def to_tesseract(code) when is_atom(code), do: to_tesseract(Atom.to_string(code))

  def to_tesseract(code) when is_binary(code) do
    code
    |> String.split("+", trim: true)
    |> Enum.map_join("+", &translate_one/1)
  end

  @doc """
  Inverse of `to_tesseract/1`: returns the ISO 639-1 code for a Tesseract
  trained-data code when one exists, otherwise the input unchanged.

  ### Examples

      iex> ImageOcr.Languages.from_tesseract("eng")
      "en"

      iex> ImageOcr.Languages.from_tesseract("frk")
      "frk"

  """
  @spec from_tesseract(String.t()) :: String.t()
  def from_tesseract(tess_code) when is_binary(tess_code) do
    Map.get(@reverse, tess_code, tess_code)
  end

  @doc false
  def known_iso639_1, do: Map.keys(@iso639_1)

  @doc false
  def known_bcp47, do: Map.keys(@bcp47)

  defp translate_one(code) do
    cond do
      Map.has_key?(@bcp47, code) ->
        Map.fetch!(@bcp47, code)

      Map.has_key?(@iso639_1, code) ->
        Map.fetch!(@iso639_1, code)

      String.contains?(code, "-") ->
        raise ArgumentError, "unknown BCP-47 language tag: #{inspect(code)}"

      String.length(code) == 2 ->
        if code == "zh" do
          raise ArgumentError,
                "ambiguous language code \"zh\" — use \"zh-Hans\" (Simplified) or \"zh-Hant\" (Traditional)"
        else
          raise ArgumentError, "unknown ISO 639-1 language code: #{inspect(code)}"
        end

      true ->
        # Tesseract code (eng, chi_sim, frk, osd, script/Latin, …) — pass
        # through unchanged.
        code
    end
  end
end

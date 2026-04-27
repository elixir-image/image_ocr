defmodule ImageOcr.Input do
  @moduledoc """
  Normalises supported OCR inputs into a `Vix.Vips.Image.t()` and an associated
  raw pixel buffer suitable for handing to the Tesseract NIF.

  Supported inputs:

  * `%Vix.Vips.Image{}` — used directly.

  * A binary that is an existing file path — loaded with
    `Vix.Vips.Image.new_from_file/1`.

  * A binary containing encoded image data (PNG, JPEG, TIFF, …) — loaded
    with `Vix.Vips.Image.new_from_buffer/1`.

  """

  alias Vix.Vips.Image, as: VImage
  alias Vix.Vips.Operation

  @typedoc """
  An accepted OCR input. See the moduledoc for resolution rules.
  """
  @type t :: VImage.t() | Path.t() | binary()

  @doc """
  Loads `input` as a `Vix.Vips.Image.t()`.

  ### Arguments

  * `input` is one of the values described in the moduledoc.

  ### Returns

  * `{:ok, image}` on success.

  * `{:error, reason}` if the input cannot be interpreted as an image.

  """
  @spec to_vimage(t()) :: {:ok, VImage.t()} | {:error, term()}
  def to_vimage(%VImage{} = image), do: {:ok, image}

  def to_vimage(binary) when is_binary(binary) do
    cond do
      looks_like_path?(binary) and File.exists?(binary) ->
        VImage.new_from_file(binary)

      byte_size(binary) >= 4 ->
        VImage.new_from_buffer(binary)

      true ->
        {:error, {:unsupported_input, :binary_too_small}}
    end
  end

  def to_vimage(charlist) when is_list(charlist) do
    case List.to_string(charlist) do
      path when is_binary(path) -> to_vimage(path)
      _ -> {:error, {:unsupported_input, :invalid_charlist}}
    end
  end

  def to_vimage(other), do: {:error, {:unsupported_input, other}}

  @doc """
  Returns a tightly-packed 8-bit pixel buffer for `image`, ready to feed to
  the Tesseract NIF.

  The image is normalised in two ways:

  * Down-cast to 8 bits per band when needed.

  * Constrained to 1 band (grayscale) or 3 bands (RGB). 4-band RGBA images
    are flattened against an opaque white background; 2-band images are
    reduced to grayscale.

  ### Arguments

  * `image` is a `Vix.Vips.Image.t()`.

  ### Returns

  * `{:ok, %{pixels: binary, width: pos_integer, height: pos_integer,
    bytes_per_pixel: 1 | 3, bytes_per_line: pos_integer}}` on success.

  * `{:error, reason}` on failure.

  """
  @spec to_pixel_buffer(VImage.t()) :: {:ok, map()} | {:error, term()}
  def to_pixel_buffer(%VImage{} = image) do
    with {:ok, normalised} <- normalise(image),
         {:ok, binary} <- VImage.write_to_binary(normalised) do
      width = VImage.width(normalised)
      height = VImage.height(normalised)
      bands = VImage.bands(normalised)

      {:ok,
       %{
         pixels: binary,
         width: width,
         height: height,
         bytes_per_pixel: bands,
         bytes_per_line: width * bands
       }}
    end
  end

  defp normalise(image) do
    image
    |> ensure_8bit()
    |> ensure_supported_bands()
  end

  defp ensure_8bit(image) do
    case VImage.format(image) do
      :VIPS_FORMAT_UCHAR -> {:ok, image}
      _ -> Operation.cast(image, :VIPS_FORMAT_UCHAR)
    end
  end

  defp ensure_supported_bands({:ok, image}) do
    case VImage.bands(image) do
      1 ->
        {:ok, image}

      3 ->
        {:ok, image}

      4 ->
        Operation.flatten(image, background: [255.0, 255.0, 255.0])

      2 ->
        Operation.extract_band(image, 0, n: 1)

      n when n > 4 ->
        Operation.extract_band(image, 0, n: 3)

      _ ->
        {:error, :unsupported_band_count}
    end
  end

  defp ensure_supported_bands({:error, _} = error), do: error

  defp looks_like_path?(binary) do
    byte_size(binary) < 4096 and not String.contains?(binary, <<0>>) and
      String.printable?(binary)
  end
end

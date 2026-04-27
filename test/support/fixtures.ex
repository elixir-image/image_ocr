defmodule ImageOcr.TestFixtures do
  @moduledoc false

  alias Vix.Vips.Operation

  @doc """
  Returns a `Vix.Vips.Image.t()` showing `text` rendered black-on-white with
  enough padding for Tesseract layout analysis.
  """
  def text_image(text, options \\ []) do
    dpi = Keyword.get(options, :dpi, 300)
    pad = Keyword.get(options, :pad, 40)

    {raw, _} = Operation.text!(text, dpi: dpi)
    {:ok, inverted} = Operation.invert(raw)

    width = Vix.Vips.Image.width(inverted)
    height = Vix.Vips.Image.height(inverted)

    {:ok, padded} =
      Operation.embed(inverted, pad, pad, width + pad * 2, height + pad * 2,
        extend: :VIPS_EXTEND_WHITE
      )

    padded
  end

  @doc """
  Writes the given image as a PNG to a freshly created temporary file and
  returns the path. The caller is responsible for deletion (e.g. via
  `on_exit/1`).
  """
  def text_image_file(text, options \\ []) do
    image = text_image(text, options)

    path =
      Path.join(System.tmp_dir!(), "image_ocr_test_#{System.unique_integer([:positive])}.png")

    :ok = Vix.Vips.Image.write_to_file(image, path)
    path
  end

  @doc """
  Returns the encoded PNG bytes for the given text image.
  """
  def text_image_png_bytes(text, options \\ []) do
    image = text_image(text, options)
    {:ok, bytes} = Vix.Vips.Image.write_to_buffer(image, ".png")
    bytes
  end
end

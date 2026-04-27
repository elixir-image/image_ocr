defmodule ImageOcr.Nif do
  @moduledoc false

  @on_load :load_nif

  def load_nif do
    path = :filename.join(:code.priv_dir(:image_ocr), ~c"image_ocr_nif")
    :erlang.load_nif(path, 0)
  end

  def init_nif(_language, _datapath, _psm), do: :erlang.nif_error(:nif_not_loaded)

  def set_variable_nif(_api, _key, _value), do: :erlang.nif_error(:nif_not_loaded)

  def recognize_nif(_api, _pixels, _w, _h, _bpp, _bpl),
    do: :erlang.nif_error(:nif_not_loaded)

  def recognize_with_boxes_nif(_api, _pixels, _w, _h, _bpp, _bpl),
    do: :erlang.nif_error(:nif_not_loaded)

  def tesseract_version_nif, do: :erlang.nif_error(:nif_not_loaded)
end

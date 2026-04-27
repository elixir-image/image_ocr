# Changelog

## 0.1.0 (initial release)

* NIF binding to Tesseract 5.x via `tesseract::TessBaseAPI`.
* `ImageOcr.new/1`, `ImageOcr.read_text/3`, `ImageOcr.recognize/3`,
  `ImageOcr.quick_read/2`, `ImageOcr.tesseract_version/0`.
* `ImageOcr.Input` accepts `Vix.Vips.Image.t()`, file paths, and in-memory
  encoded image binaries.
* `ImageOcr.Pool` — `NimblePool`-backed pool of OCR instances for parallel
  recognition.
* `ImageOcr.Tessdata` for trained-data path resolution. Lookup order:
  explicit `:datapath` option → `:image_ocr, :tessdata_path` config →
  `TESSDATA_PREFIX` env var → vendored `priv/tessdata/`.
* Vendored English (`eng`) trained-data from `tessdata_fast`.
* Mix tasks: `image_ocr.tessdata.{add,update,list,remove}`.

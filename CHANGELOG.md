# Changelog

## 0.1.0 (initial release)

### Core

* NIF binding to Tesseract 5.x (`tesseract::TessBaseAPI`) built with `elixir_make`. Refuses to build against Tesseract < 5.0.

* All recognition entry points are dirty-CPU-bound NIFs and do not block normal schedulers.

* Per-instance `ErlNifMutex` so accidental concurrent use of a single instance degrades to serialisation rather than undefined behaviour.

### API

* `Image.OCR.new/1` — build a reusable OCR instance with `:locale`, `:datapath`, `:psm`, `:variables` options.

* `Image.OCR.read_text/3` — recognise text into a UTF-8 string.

* `Image.OCR.recognize/3` — per-word results with confidence and bounding boxes.

* `Image.OCR.quick_read/2` — one-shot convenience.

* `Image.OCR.tesseract_version/0` — linked Tesseract library version.

### Inputs

* `Image.OCR.Input` accepts `Vix.Vips.Image.t()`, file paths, charlists, and in-memory binaries of encoded image data (PNG, JPEG, TIFF, …).

* Auto-normalisation of pixel format (cast to 8-bit, RGBA flatten, band reduction) before recognition.

### Concurrency

* `Image.OCR.Pool` — `NimblePool`-backed pool of OCR instances. One `TessBaseAPI*` per worker for true parallelism. Pool size defaults to `System.schedulers_online()`.

### Locales

* The `:locale` option on `Image.OCR.new/1` accepts ISO 639-1 codes (`"en"`, `:fr`), BCP-47 region/script tags (`"zh-Hans"`, `"sr-Latn"`), Tesseract codes verbatim (`"frk"`, `"osd"`), and `+`-joined combinations (`"en+fr"`).

* `"zh"` is rejected as ambiguous — callers must use `"zh-Hans"` or `"zh-Hant"`.

* Optional [`:localize`](https://hex.pm/packages/localize) dependency enables full BCP-47 parsing (`"en-US"`, `"fr-CA"`, `"zh-Hans-CN"`, `"sr-Latn-RS"`). Compile-fenced — Localize is not required.

### Trained data

* `Image.OCR.Tessdata` resolves the trained-data directory in this order: explicit `:datapath` option → `:image_ocr, :tessdata_path` config → `TESSDATA_PREFIX` env → vendored `priv/tessdata/`.

* English (`eng`) `tessdata_fast` is vendored so the package is usable out of the box.

* Mix tasks: `image.ocr.tessdata.{add,update,list,remove}` accept the same language identifiers as the runtime API. `--variant` selects `fast` (default), `best`, or `legacy`.

### Tooling

* CI matrix across Elixir 1.17 / 1.18 / 1.19 / 1.20-rc and OTP 26 / 27 / 28. Lint cell runs `mix format --check-formatted` and `mix dialyzer`.

* Dialyzer configured with `plt_add_apps: [:mix, :inets, :ssl, :public_key, :ex_unit]`.

* Demo Livebook at `livebooks/demo.livemd`.

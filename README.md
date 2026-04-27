# ImageOcr

Idiomatic Elixir interface to the [Tesseract](https://github.com/tesseract-ocr/tesseract)
OCR engine. Implemented as a NIF over the Tesseract 5.x C++ API; accepts
`Vix.Vips.Image` structs, file paths, or in-memory image binaries and returns
recognised text.

## Requirements

* Tesseract **≥ 5.0** and Leptonica installed at build time, with both
  reachable via `pkg-config`.

  ```bash
  # macOS
  brew install tesseract leptonica

  # Debian / Ubuntu
  apt-get install libtesseract-dev libleptonica-dev pkg-config

  # Alpine
  apk add tesseract-ocr-dev leptonica-dev pkg-config
  ```

* Elixir **≥ 1.20-rc** and OTP 27 or 28.

## Installation

```elixir
def deps do
  [
    {:image_ocr, "~> 0.1.0"}
  ]
end
```

Build the NIF on first compile:

```bash
mix deps.get
mix compile
```

`image_ocr` ships the English (`eng`) `tessdata_fast` model in `priv/tessdata/`
so the package is usable out of the box.

## Quick start

```elixir
{:ok, ocr}  = ImageOcr.new()                       # defaults to language: "en"
{:ok, text} = ImageOcr.read_text(ocr, "page.png")
```

`read_text/3` accepts:

* a `Vix.Vips.Image.t()` — used directly
* a path to an image file — loaded via `Vix.Vips.Image.new_from_file/1`
* an in-memory binary of encoded image data (PNG, JPEG, TIFF, …) — loaded
  via `Vix.Vips.Image.new_from_buffer/1`

For per-word output with confidence and bounding boxes, use
`ImageOcr.recognize/3`:

```elixir
{:ok, words} = ImageOcr.recognize(ocr, image)
# => [%{text: "Hello", confidence: 96.4, bbox: {32, 18, 198, 64}}, …]
```

## Concurrency

A single `ImageOcr` instance wraps one `tesseract::TessBaseAPI`, which is **not
safe for concurrent use**. The NIF guards each instance with a mutex so
accidental sharing degrades to serialisation rather than UB, but for real
parallelism you want one instance per worker. The simplest way is the
included pool:

```elixir
children = [
  {ImageOcr.Pool, name: MyOcr, language: "eng", pool_size: 4}
]

Supervisor.start_link(children, strategy: :one_for_one)

{:ok, text} = ImageOcr.Pool.read_text(MyOcr, "page.png")
```

`pool_size` defaults to `System.schedulers_online()`. Each worker holds the
loaded language model in memory — typically 2–50 MB depending on the language
and trained-data variant — so size deliberately if you also load multiple
languages or run on small hosts.

Recognition runs on dirty CPU schedulers, so it does not block the normal
schedulers regardless of pool size.

## Trained-data (`tessdata`)

The trained-data directory is resolved in this order:

1. The `:datapath` option passed to `ImageOcr.new/1`.
2. `Application.get_env(:image_ocr, :tessdata_path)`.
3. The `TESSDATA_PREFIX` environment variable.
4. The vendored fallback at `priv/tessdata/`.

Configure a project-wide location once:

```elixir
# config/config.exs
config :image_ocr, tessdata_path: "/var/lib/image_ocr/tessdata"
```

### Mix tasks

Manage trained-data files without leaving your project:

```bash
# Install one or more languages
mix image_ocr.tessdata.add fra deu

# Use a specific variant ("fast" / "best" / "legacy") or branch
mix image_ocr.tessdata.add chi_sim --variant best

# Write to a specific directory (overrides config)
mix image_ocr.tessdata.add jpn --path /var/lib/tessdata

# Refresh every installed language to its latest upstream commit
mix image_ocr.tessdata.update

# Show what's installed
mix image_ocr.tessdata.list

# Remove a language
mix image_ocr.tessdata.remove deu
```

The tasks read from and write to the same path that `ImageOcr.new/1` does, so
there is one source of truth.

## Tesseract 4.x vs 5.x

`image_ocr` requires Tesseract 5.x (currently 5.5+) and refuses to build
against older versions. 5.x is actively maintained, ships in current LTS
distros, and runs noticeably faster than 4.x on modern CPUs thanks to better
SIMD use and float32 models. The C++ API surface we use is identical between
4.x and 5.x, so 4.1+ would likely work — but we keep the support matrix
tight.

## License

Apache-2.0.

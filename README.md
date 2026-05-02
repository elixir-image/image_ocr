# Image.OCR (image_ocr)

Idiomatic Elixir interface to the [Tesseract](https://github.com/tesseract-ocr/tesseract)
OCR engine. Implemented as a NIF over the Tesseract 5.x C++ API; accepts
`Vix.Vips.Image` structs, file paths, or in-memory image binaries and returns
recognised text.

## Requirements

* Tesseract **≥ 5.0** and Leptonica installed at build time, with both
  reachable via `pkg-config`.

  ### macOS

  ```bash
  brew install tesseract leptonica pkg-config
  ```

  Xcode Command Line Tools (for `clang++`) must be installed:
  `xcode-select --install`.

  ### Debian / Ubuntu

  ```bash
  sudo apt-get install -y \
    build-essential pkg-config \
    libtesseract-dev libleptonica-dev tesseract-ocr
  ```

  Ubuntu **24.04+** is required for Tesseract ≥ 5.0; 22.04 ships 4.x and
  will not build. On 22.04 either upgrade or install Tesseract 5 from a
  PPA / source.

  ### Fedora / RHEL / CentOS Stream

  ```bash
  sudo dnf install -y \
    gcc-c++ pkgconf-pkg-config \
    tesseract-devel leptonica-devel
  ```

  ### Arch / Manjaro

  ```bash
  sudo pacman -S base-devel pkgconf tesseract leptonica
  ```

  ### Alpine

  ```bash
  apk add build-base pkgconf tesseract-ocr-dev leptonica-dev
  ```

  ### Windows

  Native Windows builds are not supported out of the box. Use **WSL2 with
  Ubuntu 24.04** and follow the Debian/Ubuntu instructions above — this is
  the path of least resistance and is what we test against.

  Building natively requires MSYS2 / MinGW-w64 with `g++`, `pkg-config`,
  `mingw-w64-x86_64-tesseract-ocr`, and `mingw-w64-x86_64-leptonica`
  available on `PATH`. Untested upstream — patches welcome.

* Elixir **≥ 1.17** and OTP **≥ 26**.

* A working C++17 compiler (`g++` or `clang++`) and `pkg-config` on the
  build host. The NIF is built with `elixir_make` on first compile.

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
{:ok, ocr}  = Image.OCR.new()                       # defaults to language: "en"
{:ok, text} = Image.OCR.read_text(ocr, "page.png")
```

`read_text/3` accepts:

* a `Vix.Vips.Image.t()` — used directly
* a path to an image file — loaded via `Vix.Vips.Image.new_from_file/1`
* an in-memory binary of encoded image data (PNG, JPEG, TIFF, …) — loaded
  via `Vix.Vips.Image.new_from_buffer/1`

For per-word output with confidence and bounding boxes, use
`Image.OCR.recognize/3`:

```elixir
{:ok, words} = Image.OCR.recognize(ocr, image)
# => [%{text: "Hello", confidence: 96.4, bbox: {32, 18, 198, 64}}, …]
```

## Locales

The `:locale` option (and the mix-task language arguments) accept:

* **ISO 639-1** two-letter codes — `"en"`, `:en`, `"fr"`, `:de`, `"ja"`.

* **BCP-47** tags for region- or script-specific variants — `"zh-Hans"`
  (Simplified Chinese), `"zh-Hant"` (Traditional), `"sr-Latn"` (Serbian
  in Latin script), `"az-Cyrl"`. The built-in table covers the common
  cases.

* **Any BCP-47 locale** — `"en-US"`, `"fr-CA"`, `"zh-Hans-CN"`,
  `"sr-Latn-RS"` — when the optional [`:localize`](https://hex.pm/packages/localize)
  dependency is installed. With Localize, the locale is parsed and the
  language + script subtags are used to pick the right Tesseract trained
  data; territory subtags are ignored (Tesseract doesn't differentiate by
  territory).

* **Tesseract codes** verbatim — `"frk"` (German Fraktur), `"osd"`
  (orientation/script detection), `"script/Latin"`.

* **`+`-joined combinations** — `"en+fr"`, `"chi_sim+eng"`, `"ja+en"`.

`"zh"` on its own is rejected as ambiguous — use `"zh-Hans"` or
`"zh-Hant"`. See `Image.OCR.Languages` for the full mapping table.

To enable BCP-47 parsing add Localize to your project:

```elixir
def deps do
  [
    {:image_ocr, "~> 0.1.0"},
    {:localize, "~> 0.25"}
  ]
end
```

## Concurrency

A single `Image.OCR` instance wraps one `tesseract::TessBaseAPI`, which is **not
safe for concurrent use**. The NIF guards each instance with a mutex so
accidental sharing degrades to serialisation rather than UB, but for real
parallelism you want one instance per worker. The simplest way is the
included pool:

```elixir
children = [
  {Image.OCR.Pool, name: MyOcr, locale: "en", pool_size: 4}
]

Supervisor.start_link(children, strategy: :one_for_one)

{:ok, text} = Image.OCR.Pool.read_text(MyOcr, "page.png")
```

`pool_size` defaults to `System.schedulers_online()`. Each worker holds the
loaded language model in memory — typically 2–50 MB depending on the language
and trained-data variant — so size deliberately if you also load multiple
languages or run on small hosts.

Recognition runs on dirty CPU schedulers, so it does not block the normal
schedulers regardless of pool size.

## Trained-data (`tessdata`)

The trained-data directory is resolved in this order:

1. The `:datapath` option passed to `Image.OCR.new/1`.
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
# Install one or more languages (ISO 639-1 codes)
mix image.ocr.tessdata.add fr de

# BCP-47 for region/script-specific variants
mix image.ocr.tessdata.add zh-Hans zh-Hant sr-Latn

# Pick a variant: fast (default, ~2-4 MB), best (~10-15 MB), legacy (largest)
mix image.ocr.tessdata.add en --variant best

# Write to a specific directory (overrides config and TESSDATA_PREFIX)
mix image.ocr.tessdata.add ja --path /var/lib/tessdata

# Refresh every installed language to its latest upstream commit
mix image.ocr.tessdata.update

# Show what's installed
mix image.ocr.tessdata.list

# Remove a language
mix image.ocr.tessdata.remove de
```

The tasks read from and write to the same path that `Image.OCR.new/1` does, so
there is one source of truth.

## Tesseract 4.x vs 5.x

`image_ocr` requires Tesseract 5.x (currently 5.5+) and refuses to build
against older versions. 5.x is actively maintained, ships in current LTS
distros, and runs noticeably faster than 4.x on modern CPUs thanks to better
SIMD use and float32 models. The C++ API surface we use is identical between
4.x and 5.x, so 4.1+ would likely work — but we keep the support matrix
tight.

## Livebook

An interactive demonstration is at [`notebooks/demo.livemd`](notebooks/demo.livemd).
It covers one-shot OCR, reusable instances, per-word bounding boxes, the
NimblePool, PSM/SetVariable tweaks, and uploading your own image.

## License

Apache-2.0.

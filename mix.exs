defmodule ImageOcr.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/kipcole9/image_ocr"

  def project do
    [
      app: :image_ocr,
      version: @version,
      elixir: "~> 1.20-rc",
      start_permanent: Mix.env() == :prod,
      compilers: [:elixir_make] ++ Mix.compilers(),
      elixirc_paths: elixirc_paths(Mix.env()),
      make_targets: ["all"],
      make_clean: ["clean"],
      deps: deps(),
      description: description(),
      package: package(),
      docs: docs(),
      source_url: @source_url
    ]
  end

  def application do
    [
      extra_applications: [:logger, :inets, :ssl, :crypto, :public_key]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:vix, "~> 0.30"},
      {:nimble_pool, "~> 1.1"},
      {:elixir_make, "~> 0.8", runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false}
    ]
  end

  defp description do
    "Idiomatic Elixir interface to the Tesseract OCR engine via a NIF, " <>
      "accepting Vix.Vips.Image structs, file paths, or in-memory image binaries."
  end

  defp package do
    [
      maintainers: ["Kip Cole"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url},
      files: ~w(lib c_src priv/tessdata/eng.traineddata priv/tessdata/VERSION
           Makefile mix.exs README.md CHANGELOG.md LICENSE .formatter.exs)
    ]
  end

  defp docs do
    [
      main: "readme",
      extras: ["README.md", "CHANGELOG.md"],
      source_ref: "v#{@version}"
    ]
  end
end

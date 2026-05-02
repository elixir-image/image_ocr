defmodule Image.OCR.Tessdata.Manifest do
  @moduledoc false

  # Reads/writes priv/tessdata/VERSION (or wherever tessdata lives), tracking
  # the variant + commit SHA + sha256 of every vendored language file.
  #
  # Format is one line per language:
  #
  #     eng <variant> <branch> <sha256> <size> <fetched_at_iso8601>

  @filename "VERSION"

  def path(dir), do: Path.join(dir, @filename)

  def read(dir) do
    case File.read(path(dir)) do
      {:ok, content} -> parse(content)
      {:error, :enoent} -> %{}
      {:error, reason} -> {:error, reason}
    end
  end

  def write(dir, manifest) do
    File.mkdir_p!(dir)

    body =
      manifest
      |> Enum.sort_by(fn {lang, _} -> lang end)
      |> Enum.map_join("\n", fn {lang, entry} ->
        Enum.join(
          [
            lang,
            entry.variant,
            entry.branch,
            entry.sha256,
            Integer.to_string(entry.size),
            entry.fetched_at
          ],
          " "
        )
      end)

    File.write!(path(dir), body <> "\n")
    :ok
  end

  def upsert(dir, language, entry) do
    manifest =
      case read(dir) do
        m when is_map(m) -> m
        _ -> %{}
      end

    write(dir, Map.put(manifest, language, entry))
  end

  def delete(dir, language) do
    case read(dir) do
      m when is_map(m) -> write(dir, Map.delete(m, language))
      _ -> :ok
    end
  end

  defp parse(content) do
    content
    |> String.split("\n", trim: true)
    |> Enum.reduce(%{}, fn line, acc ->
      case String.split(line, " ", trim: true) do
        [lang, variant, branch, sha256, size, fetched_at] ->
          Map.put(acc, lang, %{
            variant: variant,
            branch: branch,
            sha256: sha256,
            size: String.to_integer(size),
            fetched_at: fetched_at
          })

        _ ->
          acc
      end
    end)
  end
end

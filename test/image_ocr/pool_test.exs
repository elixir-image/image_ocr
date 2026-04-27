defmodule ImageOcr.PoolTest do
  use ExUnit.Case, async: true

  import ImageOcr.TestFixtures

  setup do
    name = :"pool_#{System.unique_integer([:positive])}"
    start_supervised!({ImageOcr.Pool, name: name, pool_size: 4})
    %{pool: name}
  end

  test "read_text/3 returns recognised text", %{pool: pool} do
    image = text_image("Pool Hello")
    assert {:ok, text} = ImageOcr.Pool.read_text(pool, image)
    assert text =~ "Pool"
  end

  test "recognize/3 returns per-word results", %{pool: pool} do
    image = text_image("Words Words")
    assert {:ok, [_ | _] = words} = ImageOcr.Pool.recognize(pool, image)
    assert Enum.all?(words, &is_map/1)
  end

  test "handles concurrent checkouts with different inputs", %{pool: pool} do
    inputs =
      ["Foo", "Bar", "Baz", "Qux", "Foo Bar", "Bar Baz", "Quick brown fox", "Lazy dog"]
      |> Enum.map(&{&1, text_image(&1)})

    results =
      1..40
      |> Task.async_stream(
        fn i ->
          {expected, image} = Enum.at(inputs, rem(i, length(inputs)))
          {:ok, text} = ImageOcr.Pool.read_text(pool, image)
          {expected, String.trim(text)}
        end,
        max_concurrency: 8,
        timeout: 60_000
      )
      |> Enum.map(fn {:ok, value} -> value end)

    Enum.each(results, fn {expected, actual} ->
      assert actual =~ expected |> String.split() |> hd()
    end)
  end
end

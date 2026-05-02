defmodule Image.OCR.ConcurrencyTest do
  use ExUnit.Case, async: true

  import Image.OCR.TestFixtures

  @phrases [
    "Alpha bravo",
    "Charlie delta",
    "Echo foxtrot",
    "Golf hotel",
    "India juliet",
    "Kilo lima",
    "Mike november",
    "Oscar papa"
  ]

  test "shared instance serialises correctly under heavy concurrency" do
    {:ok, ocr} = Image.OCR.new()
    images = Enum.map(@phrases, &{&1, text_image(&1)})

    results =
      1..32
      |> Task.async_stream(
        fn i ->
          {phrase, image} = Enum.at(images, rem(i, length(images)))
          {:ok, text} = Image.OCR.read_text(ocr, image)
          {phrase, String.trim(text)}
        end,
        max_concurrency: 8,
        ordered: false,
        timeout: 60_000
      )
      |> Enum.map(fn {:ok, value} -> value end)

    assert length(results) == 32

    Enum.each(results, fn {expected, actual} ->
      assert actual =~ String.split(expected) |> hd()
    end)
  end

  test "per-task instances run in parallel without crashes" do
    images = Enum.map(@phrases, &text_image/1)

    results =
      1..(System.schedulers_online() * 2)
      |> Task.async_stream(
        fn i ->
          {:ok, ocr} = Image.OCR.new()
          image = Enum.at(images, rem(i, length(images)))
          Image.OCR.read_text(ocr, image)
        end,
        max_concurrency: System.schedulers_online(),
        timeout: 60_000
      )
      |> Enum.map(fn {:ok, result} -> result end)

    assert Enum.all?(results, &match?({:ok, _}, &1))
  end

  test "instance is garbage-collected without crashing the VM" do
    # Pass :datapath explicitly so this test is not sensitive to other test
    # modules transiently mutating the :tessdata_path application env.
    datapath = Image.OCR.Tessdata.vendored_path()

    Enum.each(1..50, fn _ ->
      {:ok, _ocr} = Image.OCR.new(datapath: datapath)
    end)

    :erlang.garbage_collect()
    # If we reached here without a SIGSEGV, the resource destructor is sound.
    assert true
  end
end

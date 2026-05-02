defmodule Image.OCR.Pool do
  @moduledoc """
  A `NimblePool`-backed pool of `Image.OCR` instances for concurrent OCR.

  Each pool worker owns one `Image.OCR` instance — and therefore one
  `tesseract::TessBaseAPI*`. Because each instance is single-threaded, the
  pool is the simplest way to get parallel recognition across many processes
  without sharing state.

  ## Sizing

  The default pool size is `System.schedulers_online()`, matching the number
  of dirty-CPU schedulers Tesseract recognition runs on. Each worker holds
  the loaded language model in memory (typically 2–50 MB depending on the
  language and trained-data variant), so size the pool deliberately.

  ## Example

      children = [
        {Image.OCR.Pool, name: MyOcr, locale: "en", pool_size: 4}
      ]
      Supervisor.start_link(children, strategy: :one_for_one)

      {:ok, text} = Image.OCR.Pool.read_text(MyOcr, "page.png")

  """

  @behaviour NimblePool

  @default_checkout_timeout 30_000

  @doc """
  Starts a pool linked to the calling process.

  ### Arguments

  * `options` is a keyword list. See the options below.

  ### Options

  * `:name` is the registered name for the pool. Required.

  * `:pool_size` is the number of worker processes (and therefore Tesseract
    instances) to run. Defaults to `System.schedulers_online()`.

  * `:lazy` controls lazy worker initialisation. Defaults to `false`.

  * Remaining options are passed straight to `Image.OCR.new/1` (`:locale`,
    `:datapath`, `:psm`, `:variables`).

  ### Returns

  * `{:ok, pid}` on success.

  * `{:error, reason}` on failure.

  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options) do
    {pool_size, options} = Keyword.pop(options, :pool_size, System.schedulers_online())
    {lazy, options} = Keyword.pop(options, :lazy, false)
    {name, options} = Keyword.pop(options, :name)
    name || raise ArgumentError, "Image.OCR.Pool requires a :name option"

    NimblePool.start_link(
      worker: {__MODULE__, options},
      pool_size: pool_size,
      lazy: lazy,
      name: name
    )
  end

  @doc """
  Standard supervisor child spec.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(options) do
    %{
      id: Keyword.get(options, :name, __MODULE__),
      start: {__MODULE__, :start_link, [options]},
      type: :worker
    }
  end

  @doc """
  Recognises text in `input` using a worker checked out from `pool`.

  ### Arguments

  * `pool` is the registered name of the pool.

  * `input` is any value accepted by `Image.OCR.read_text/2`.

  * `options` accepts `:timeout` (defaults to 30_000 ms).

  ### Returns

  * `{:ok, text}` on success.

  * `{:error, reason}` on failure.

  """
  @spec read_text(NimblePool.pool(), Image.OCR.Input.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def read_text(pool, input, options \\ []) do
    timeout = Keyword.get(options, :timeout, @default_checkout_timeout)

    NimblePool.checkout!(
      pool,
      :checkout,
      fn _from, instance ->
        {Image.OCR.read_text(instance, input), :ok}
      end,
      timeout
    )
  end

  @doc """
  Recognises `input` and returns per-word results. See `Image.OCR.recognize/3`.

  """
  @spec recognize(NimblePool.pool(), Image.OCR.Input.t(), keyword()) ::
          {:ok, [Image.OCR.word_result()]} | {:error, term()}
  def recognize(pool, input, options \\ []) do
    timeout = Keyword.get(options, :timeout, @default_checkout_timeout)

    NimblePool.checkout!(
      pool,
      :checkout,
      fn _from, instance ->
        {Image.OCR.recognize(instance, input), :ok}
      end,
      timeout
    )
  end

  # NimblePool callbacks

  @impl NimblePool
  def init_pool(options), do: {:ok, options}

  @impl NimblePool
  def init_worker(options) do
    case Image.OCR.new(options) do
      {:ok, instance} -> {:ok, instance, options}
      {:error, reason} -> {:stop, {:image_ocr_init_failed, reason}}
    end
  end

  @impl NimblePool
  def handle_checkout(:checkout, _from, instance, options) do
    {:ok, instance, instance, options}
  end

  @impl NimblePool
  def handle_checkin(:ok, _from, instance, options) do
    {:ok, instance, options}
  end

  @impl NimblePool
  def terminate_worker(_reason, _instance, options) do
    # The TessBaseAPI is freed in the NIF resource destructor when the
    # instance is garbage-collected — nothing to do here.
    {:ok, options}
  end
end

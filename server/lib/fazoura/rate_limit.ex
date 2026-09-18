defmodule Fazoura.RateLimit do
  @moduledoc """
  Fixed-window request counting, per caller and bucket.

  Creating a room or uploading a photo costs the server memory and disk but costs the
  caller nothing, so the expensive endpoints are metered (`FazouraWeb.Plugs.RateLimit`).
  This is deliberately small: one ETS table of counters, swept periodically. It is a flood
  stop, not a fairness mechanism, and it counts per node — which is all a single-VPS
  deployment has (AGENTS.md §6).

  A fixed window lets a caller spend two windows' worth of requests across a boundary.
  That is accepted: the limits are far above real use, and the point is to bound the
  sustained rate, not to police bursts precisely.
  """

  use GenServer

  @table __MODULE__
  # Counters are only useful for the window they belong to; sweep the stale ones so a
  # long-running server doesn't accumulate a row per caller seen.
  @sweep_every :timer.minutes(5)

  @type bucket :: atom()

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Counts one request from `key` against `bucket`.

  Returns `:ok` while at or under `limit` requests per `window_ms`, and
  `{:error, :rate_limited}` once over. Missing table (not started, as in some unit
  tests) means no limiting rather than a crash.
  """
  @spec check(bucket(), String.t(), pos_integer(), pos_integer()) ::
          :ok | {:error, :rate_limited}
  def check(bucket, key, limit, window_ms) do
    # The window's start in ms, so a sweep can compare it to wall-clock time without
    # knowing which window length any particular bucket used.
    window_start = div(now_ms(), window_ms) * window_ms

    count =
      :ets.update_counter(
        @table,
        {bucket, key, window_start},
        {2, 1},
        {{bucket, key, window_start}, 0}
      )

    if count > limit, do: {:error, :rate_limited}, else: :ok
  rescue
    ArgumentError -> :ok
  end

  @doc "Forgets every counter. Tests only."
  @spec reset() :: :ok
  def reset do
    :ets.delete_all_objects(@table)
    :ok
  rescue
    ArgumentError -> :ok
  end

  ## Callbacks

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set, write_concurrency: true])
    schedule_sweep()
    {:ok, %{}}
  end

  @impl true
  def handle_info(:sweep, state) do
    sweep()
    schedule_sweep()
    {:noreply, state}
  end

  # A window that started before the last sweep interval can no longer be current for
  # any bucket this module uses, so its counter is spent.
  defp sweep do
    cutoff = now_ms() - @sweep_every
    :ets.select_delete(@table, [{{{:_, :_, :"$1"}, :_}, [{:<, :"$1", cutoff}], [true]}])
  rescue
    ArgumentError -> 0
  end

  defp schedule_sweep, do: Process.send_after(self(), :sweep, @sweep_every)

  defp now_ms, do: System.system_time(:millisecond)
end

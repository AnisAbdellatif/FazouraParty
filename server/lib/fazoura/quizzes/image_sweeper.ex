defmodule Fazoura.Quizzes.ImageSweeper do
  @moduledoc """
  Runs `Fazoura.Quizzes.sweep_images/1` on an interval so unpublished and replaced
  quizzes don't leave their photos on disk forever.

  Configured under `config :fazoura, :image_sweeper` — `:interval_ms`, `:grace_seconds`
  and `:enabled` (false in test, where sweeping is exercised directly).
  """

  use GenServer

  require Logger

  alias Fazoura.Quizzes

  @defaults [enabled: true, interval_ms: :timer.hours(1), grace_seconds: 86_400]

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Sweeps now and returns what it freed. Mostly for the console and tests."
  @spec sweep_now(timeout()) :: map()
  def sweep_now(timeout \\ 30_000), do: GenServer.call(__MODULE__, :sweep, timeout)

  @doc "The child spec, or nil when sweeping is disabled."
  @spec child_spec_if_enabled() :: Supervisor.child_spec() | nil
  def child_spec_if_enabled do
    if settings()[:enabled], do: child_spec([])
  end

  @impl true
  def init(opts) do
    config = Keyword.merge(settings(), opts)
    # The first sweep waits out the boot: nothing is more urgent than serving requests.
    {:ok, schedule(%{config: config, timer: nil}, config[:interval_ms])}
  end

  @impl true
  def handle_call(:sweep, _from, state), do: {:reply, sweep(state), state}

  @impl true
  def handle_info(:sweep, state) do
    sweep(state)
    {:noreply, schedule(state, state.config[:interval_ms])}
  end

  defp sweep(state) do
    freed = Quizzes.sweep_images(grace_seconds: state.config[:grace_seconds])

    if freed.images > 0 or freed.files > 0 do
      Logger.info(
        "swept #{freed.images} orphaned image(s) and #{freed.files} stray file(s), " <>
          "#{freed.bytes} bytes"
      )
    end

    freed
  rescue
    error ->
      # A sweep is housekeeping: a failure must never take the server down with it.
      Logger.error("image sweep failed: #{Exception.message(error)}")
      %{images: 0, files: 0, bytes: 0}
  end

  defp schedule(state, interval) do
    if state.timer, do: Process.cancel_timer(state.timer)
    %{state | timer: Process.send_after(self(), :sweep, interval)}
  end

  defp settings, do: Keyword.merge(@defaults, Application.get_env(:fazoura, :image_sweeper, []))
end

defmodule Fazoura.Quizzes.ModerationSweeper do
  @moduledoc """
  Forgets moderation records once they have been decided and the decision has
  aged out — dismissed reports (`Fazoura.Quizzes.Reports.sweep/1`) and approved
  or rejected submissions (`Fazoura.Quizzes.Review.sweep/1`).

  Both hold things written about people: a report is somebody's account of what
  is wrong with a quiz, in their own words, and a rejected submission holds a
  title and the reason it was turned down. They are worth keeping while they
  are being acted on and briefly after, and then they are not (GDPR
  Art. 5(1)(e) — kept no longer than the purpose needs).

  Nothing waiting is ever swept. An open report and a pending submission are
  the queues themselves, and emptying those is a person's job, not a timer's.

  Configured under `config :fazoura, :moderation_sweeper` — `:interval_ms`,
  `:retention_days` and `:enabled` (false in test, where sweeping is exercised
  directly).
  """

  use GenServer

  require Logger

  alias Fazoura.Quizzes.{Reports, Review}

  # Six hours rather than a day: this server restarts on every deploy, and a
  # sweep scheduled a day out would often never arrive.
  @defaults [enabled: true, interval_ms: :timer.hours(6), retention_days: 90]

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Sweeps now and returns what it forgot. Mostly for the console and tests."
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
    opts = [retention_days: state.config[:retention_days]]
    forgotten = %{reports: Reports.sweep(opts), submissions: Review.sweep(opts)}

    if forgotten.reports > 0 or forgotten.submissions > 0 do
      Logger.info(
        "swept #{forgotten.reports} answered report(s) and " <>
          "#{forgotten.submissions} decided submission(s)"
      )
    end

    forgotten
  rescue
    error ->
      # Housekeeping: a failure must never take the server down with it.
      Logger.error("moderation sweep failed: #{Exception.message(error)}")
      %{reports: 0, submissions: 0}
  end

  defp schedule(state, interval) do
    if state.timer, do: Process.cancel_timer(state.timer)
    %{state | timer: Process.send_after(self(), :sweep, interval)}
  end

  defp settings,
    do: Keyword.merge(@defaults, Application.get_env(:fazoura, :moderation_sweeper, []))
end

defmodule Fazoura.Rooms.Drain do
  @moduledoc """
  Ends live games politely when the server is going down.

  Games are in memory only — surviving a restart is a v1 non-goal (AGENTS.md §2) — so a
  deploy always ends every party. What this avoids is ending them *silently*: the
  supervisor stops children in reverse order, so this process, started last, terminates
  before the endpoint. It asks every room to close with `shutdown`, then waits long
  enough for those pushes to reach the sockets that are still open. Clients then show
  "the party ended" instead of reconnecting into `room_not_found`.

  `config :fazoura, :drain_ms` sets how long to wait for those pushes (0 closes the
  rooms without waiting, which is what tests want).
  """

  use GenServer

  require Logger

  alias Fazoura.Rooms

  @default_drain_ms 500

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Child spec with a shutdown budget that outlasts the drain wait."
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      shutdown: drain_ms(opts) + 5_000
    }
  end

  @impl true
  def init(opts) do
    Process.flag(:trap_exit, true)
    {:ok, %{drain_ms: drain_ms(opts)}}
  end

  @impl true
  def terminate(_reason, state) do
    case Rooms.shutdown_all() do
      0 ->
        :ok

      count ->
        Logger.info("draining #{count} live room(s) before shutdown")
        if state.drain_ms > 0, do: Process.sleep(state.drain_ms)
        :ok
    end
  end

  defp drain_ms(opts) do
    Keyword.get_lazy(opts, :drain_ms, fn ->
      Application.get_env(:fazoura, :drain_ms, @default_drain_ms)
    end)
  end
end

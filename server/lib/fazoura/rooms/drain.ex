defmodule Fazoura.Rooms.Drain do
  @moduledoc """
  Ends live games politely when the server is going down.

  Games are in memory only — surviving a restart is a v1 non-goal (AGENTS.md §2) — so a
  deploy always ends every party. What this avoids is ending them *silently*: the
  supervisor stops children in reverse order, so this process, started last, terminates
  before the endpoint. It asks every room to close with `shutdown`, then waits long
  enough for those pushes to reach the sockets that are still open. Clients then show
  "the party ended" instead of reconnecting into `room_not_found`.

  A deploy asks for the same thing earlier, with `SIGUSR2`. kamal-proxy moves traffic to
  the new container and cuts the old one's WebSockets *before* the old one is stopped, so
  by the time `SIGTERM` arrives nobody is left to hear `shutdown`. The deploy's
  `pre-app-boot` step (`.kamal/steps/drain-rooms`) signals the running container before
  the new one starts; its rooms close out loud while their sockets are still open, and
  the container carries on serving until it is replaced. A BEAM without this handler —
  an older image — is PID 1 with no handler for the signal, which the kernel then drops.

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
    listen_for_signal()
    {:ok, %{drain_ms: drain_ms(opts)}}
  end

  @impl true
  def handle_info(:drain, state) do
    case Rooms.shutdown_all() do
      0 -> :ok
      count -> Logger.info("closing #{count} live room(s): a new server is taking over")
    end

    {:noreply, state}
  end

  def handle_info(_message, state), do: {:noreply, state}

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

  # The runtime delivers OS signals it handles as events to `:erl_signal_server`; the
  # handler there is ours for SIGUSR2, and once only, however often this restarts.
  defp listen_for_signal do
    :ok = :os.set_signal(:sigusr2, :handle)

    if __MODULE__.Signal not in :gen_event.which_handlers(:erl_signal_server) do
      :ok = :gen_event.add_handler(:erl_signal_server, __MODULE__.Signal, [])
    end
  end

  defp drain_ms(opts) do
    Keyword.get_lazy(opts, :drain_ms, fn ->
      Application.get_env(:fazoura, :drain_ms, @default_drain_ms)
    end)
  end
end

defmodule Fazoura.Rooms.Drain.Signal do
  @moduledoc false
  # SIGUSR2, as `:erl_signal_server` hands it on: ask `Fazoura.Rooms.Drain` to close
  # every room. Every other signal is left to the runtime's own handler.

  @behaviour :gen_event

  @impl true
  def init(_args), do: {:ok, nil}

  @impl true
  def handle_event(:sigusr2, state) do
    if pid = Process.whereis(Fazoura.Rooms.Drain), do: send(pid, :drain)
    {:ok, state}
  end

  def handle_event(_signal, state), do: {:ok, state}

  @impl true
  def handle_call(_request, state), do: {:ok, :ok, state}
end

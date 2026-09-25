defmodule Fazoura.Rooms.DrainTest do
  # Draining closes every room on the node, so it must not run beside other tests.
  use FazouraWeb.ChannelCase, async: false

  alias Fazoura.QuizFixtures
  alias Fazoura.Rooms
  alias Fazoura.Rooms.Drain

  # Rooms live under a DynamicSupervisor, not under the test process, so rooms created
  # by the async tests in other files are still registered when this file runs. Clear
  # them, so "nothing live" here means nothing live rather than nothing leaked.
  defp drain_leaked_rooms do
    Rooms.shutdown_all()
    wait_until_no_rooms(50)
  end

  defp wait_until_no_rooms(0), do: flunk("rooms left by other tests did not stop")

  defp wait_until_no_rooms(attempts) do
    case Rooms.active() do
      [] ->
        :ok

      _still_closing ->
        Process.sleep(10)
        wait_until_no_rooms(attempts - 1)
    end
  end

  test "a shutdown ends live games out loud instead of by silence" do
    {:ok, code, _host_token} = Rooms.create(QuizFixtures.pack())
    {:ok, _reply, socket} = join_room(code, %{"display_name" => "Sam"})
    Process.unlink(socket.channel_pid)

    # What the Drain process does on its way down, while sockets are still open.
    assert Drain.terminate(:shutdown, %{drain_ms: 0}) == :ok

    assert_push "room_closed", %{reason: "shutdown"}
    assert {:error, %{code: "room_not_found"}} = join_room(code, %{"display_name" => "Late"})
  end

  test "SIGUSR2 ends live games out loud and leaves the server running" do
    # A deploy signals the running container before the new one starts: kamal-proxy
    # cuts its WebSockets at the switch, before SIGTERM could be heard.
    {:ok, code, _host_token} = Rooms.create(QuizFixtures.pack())
    {:ok, _reply, socket} = join_room(code, %{"display_name" => "Sam"})
    Process.unlink(socket.channel_pid)

    # Where the runtime delivers the OS signal.
    :gen_event.notify(:erl_signal_server, :sigusr2)

    assert_push "room_closed", %{reason: "shutdown"}
    assert Process.alive?(Process.whereis(Drain))
    assert {:ok, _code, _token} = Rooms.create(QuizFixtures.pack())
  end

  test "with nothing live it does nothing" do
    drain_leaked_rooms()

    assert Rooms.active() == []
    assert Drain.terminate(:shutdown, %{drain_ms: 500}) == :ok
  end

  test "the child spec outlasts the drain wait, so the supervisor doesn't kill it" do
    assert %{id: Drain, shutdown: shutdown} = Drain.child_spec(drain_ms: 2_000)
    assert shutdown > 2_000
  end
end

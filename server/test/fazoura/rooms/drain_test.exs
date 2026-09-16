defmodule Fazoura.Rooms.DrainTest do
  # Draining closes every room on the node, so it must not run beside other tests.
  use FazouraWeb.ChannelCase, async: false

  alias Fazoura.QuizFixtures
  alias Fazoura.Rooms
  alias Fazoura.Rooms.Drain

  defp join_room(code, payload) do
    socket(FazouraWeb.UserSocket, nil, %{})
    |> join(FazouraWeb.RoomChannel, "room:" <> code, Map.put(payload, "protocol_version", 4))
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

  test "with nothing live it does nothing" do
    assert Rooms.active() == []
    assert Drain.terminate(:shutdown, %{drain_ms: 500}) == :ok
  end

  test "the child spec outlasts the drain wait, so the supervisor doesn't kill it" do
    assert %{id: Drain, shutdown: shutdown} = Drain.child_spec(drain_ms: 2_000)
    assert shutdown > 2_000
  end
end

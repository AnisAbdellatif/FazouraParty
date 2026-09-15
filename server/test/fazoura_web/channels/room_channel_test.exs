defmodule FazouraWeb.RoomChannelTest do
  use FazouraWeb.ChannelCase, async: true

  alias Fazoura.Game.Pack
  alias Fazoura.Rooms

  setup do
    {:ok, pack} = Pack.fetch("general-knowledge")
    {:ok, code, host_token} = Rooms.create(pack)
    %{code: code, host_token: host_token}
  end

  defp join_room(code, payload) do
    socket(FazouraWeb.UserSocket, nil, %{})
    |> join(FazouraWeb.RoomChannel, "room:" <> code, Map.put(payload, "protocol_version", 4))
  end

  test "joining pushes a full state snapshot", %{code: code} do
    assert {:ok, %{role: "player", player_id: id}, _socket} =
             join_room(code, %{"display_name" => "Sam"})

    assert_push "state", %{phase: "lobby", room_code: ^code, you: %{player_id: ^id}}
  end

  test "unknown room and bad tokens are rejected", %{code: code} do
    assert {:error, %{code: "room_not_found"}} = join_room("ZZZZZZ", %{"display_name" => "Sam"})
    assert {:error, %{code: "invalid_token"}} = join_room(code, %{"host_token" => "forged"})
    assert {:error, %{code: "invalid_token"}} = join_room(code, %{"player_token" => "forged"})
  end

  test "a host token only works for its own room", %{host_token: host_token} do
    {:ok, pack} = Pack.fetch("general-knowledge")
    {:ok, other_code, _} = Rooms.create(pack)

    assert {:error, %{code: "invalid_token"}} =
             join_room(other_code, %{"host_token" => host_token})
  end

  test "unknown events get invalid_payload", %{code: code} do
    {:ok, _, socket} = join_room(code, %{"display_name" => "Sam"})
    ref = push(socket, "cheat", %{"score" => 9000})
    assert_reply ref, :error, %{code: "invalid_payload"}
  end

  test "clients are told when the room process dies", %{code: code} do
    {:ok, _, socket} = join_room(code, %{"display_name" => "Sam"})
    Process.unlink(socket.channel_pid)
    [{room_pid, _}] = Registry.lookup(Fazoura.Rooms.Registry, code)

    Process.exit(room_pid, :kill)

    assert_push "room_closed", %{reason: "shutdown"}
    assert {:error, %{code: "room_not_found"}} = join_room(code, %{"display_name" => "Late"})
  end

  test "room closes after the host has been absent for 10 minutes" do
    {:ok, clock} = Agent.start_link(fn -> 0 end)
    {:ok, pack} = Pack.fetch("general-knowledge")
    {:ok, code, _host_token} = Rooms.create(pack, now: fn -> Agent.get(clock, & &1) end)

    {:ok, _, socket} = join_room(code, %{"display_name" => "Sam"})
    Process.unlink(socket.channel_pid)

    Agent.update(clock, &(&1 + :timer.minutes(10)))
    :ok = Rooms.tick(code)

    assert_push "room_closed", %{reason: "host_timeout"}
  end
end

defmodule FazouraWeb.RoomChannelTest do
  use FazouraWeb.ChannelCase, async: true

  alias Fazoura.QuizFixtures
  alias Fazoura.Rooms

  setup do
    pack = QuizFixtures.pack()
    {:ok, code, host_token} = Rooms.create(pack)
    %{code: code, host_token: host_token}
  end

  defp join_room(code, payload) do
    socket(FazouraWeb.UserSocket, nil, %{})
    |> join(
      FazouraWeb.RoomChannel,
      "room:" <> code,
      Map.put(payload, "protocol_version", Fazoura.Game.protocol_version())
    )
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
    pack = QuizFixtures.pack()
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

  test "a room nobody is in closes after 30 seconds" do
    {:ok, clock} = Agent.start_link(fn -> 0 end)
    pack = QuizFixtures.pack()
    {:ok, code, _host_token} = Rooms.create(pack, now: fn -> Agent.get(clock, & &1) end)
    [{room, _}] = Registry.lookup(Fazoura.Rooms.Registry, code)

    {:ok, _, socket} = join_room(code, %{"display_name" => "Sam"})
    Process.unlink(socket.channel_pid)

    # Occupied, so time passing means nothing: the old host-absence timeout is gone.
    Agent.update(clock, &(&1 + :timer.minutes(10)))
    :ok = Rooms.tick(code)
    assert Process.alive?(room)

    # Sam leaves and the room is deserted. Our :DOWN says nothing about the
    # room's, so tick once to be sure it has noticed before the clock moves on.
    ref = Process.monitor(socket.channel_pid)
    Process.exit(socket.channel_pid, :kill)
    assert_receive {:DOWN, ^ref, _, _, _}
    :ok = Rooms.tick(code)

    Agent.update(clock, &(&1 + :timer.seconds(30)))
    room_ref = Process.monitor(room)
    :ok = Rooms.tick(code)

    # The process stopping is the fact; the Registry entry clears just after.
    assert_receive {:DOWN, ^room_ref, :process, ^room, :normal}
  end
end

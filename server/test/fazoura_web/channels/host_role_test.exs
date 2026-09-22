defmodule FazouraWeb.HostRoleTest do
  @moduledoc """
  The host role moves; the room never sits hostless while anyone is still in it
  (PROTOCOL.md §3.4).

  Reported as "I left the room but /admin still shows it hosted": before v5 a host
  who walked out left the party alive but unplayable for ten minutes. These tests
  pin what replaced that.
  """

  use FazouraWeb.ChannelCase, async: true

  alias Fazoura.{Game, QuizFixtures, Rooms}

  setup do
    {:ok, code, host_token} = Rooms.create(QuizFixtures.pack())
    %{code: code, host_token: host_token}
  end

  defp join_room(code, payload) do
    socket(FazouraWeb.UserSocket, nil, %{})
    |> join(
      FazouraWeb.RoomChannel,
      "room:" <> code,
      Map.put(payload, "protocol_version", Game.protocol_major())
    )
  end

  defp join_host(code, token, name \\ nil) do
    payload = %{"host_token" => token}
    join_room(code, if(name, do: Map.put(payload, "display_name", name), else: payload))
  end

  # Kills a socket and waits for the room to notice, so the next assertion is not
  # racing the room's own :DOWN.
  defp drop(code, socket) do
    Process.unlink(socket.channel_pid)
    ref = Process.monitor(socket.channel_pid)
    Process.exit(socket.channel_pid, :kill)
    assert_receive {:DOWN, ^ref, _, _, _}
    :ok = Rooms.tick(code)
  end

  describe "host_transfer" do
    test "hands the role to a connected player, who is told they now have it", %{
      code: code,
      host_token: host_token
    } do
      {:ok, _, host} = join_host(code, host_token, "Hana")
      {:ok, %{player_id: sam}, sam_socket} = join_room(code, %{"display_name" => "Sam"})

      ref = push(host, "host_transfer", %{"player_id" => sam})
      assert_reply ref, :ok, %{}

      # Sam's own snapshot says he is the host, and carries the token that proves
      # it — nobody else receives one. Several snapshots arrive (join, then the
      # transfer), so match the one that actually carries a token.
      assert_push "state",
                  %{you: %{role: "host", player_id: ^sam, host_token: token}}
                  when is_binary(token)

      # And he can act on it.
      ref = push(sam_socket, "host_next", %{})
      assert_reply ref, :ok, %{}
    end

    test "the previous host's token stops working", %{code: code, host_token: host_token} do
      {:ok, _, host} = join_host(code, host_token, "Hana")
      {:ok, %{player_id: sam}, _} = join_room(code, %{"display_name" => "Sam"})

      ref = push(host, "host_transfer", %{"player_id" => sam})
      assert_reply ref, :ok, %{}

      # Otherwise a demoted host could simply rejoin and take the room back.
      assert {:error, %{code: "invalid_token"}} = join_host(code, host_token)
    end

    test "the former host stays in the game as an ordinary player", %{
      code: code,
      host_token: host_token
    } do
      {:ok, %{player_id: hana}, host} = join_host(code, host_token, "Hana")
      {:ok, %{player_id: sam}, _} = join_room(code, %{"display_name" => "Sam"})

      ref = push(host, "host_transfer", %{"player_id" => sam})
      assert_reply ref, :ok, %{}

      # Same identity and score; only the role moved.
      assert_push "state", %{
        players: players,
        you: %{role: "player", player_id: ^hana}
      }

      assert Enum.any?(players, &(&1.id == hana and &1.is_host == false))
      assert Enum.any?(players, &(&1.id == sam and &1.is_host == true))

      # And host intents are no longer theirs to send.
      ref = push(host, "host_next", %{})
      assert_reply ref, :error, %{code: "not_host"}
    end

    test "a player cannot transfer the role to themselves", %{code: code} do
      {:ok, %{player_id: sam}, sam_socket} = join_room(code, %{"display_name" => "Sam"})

      ref = push(sam_socket, "host_transfer", %{"player_id" => sam})
      assert_reply ref, :error, %{code: "not_host"}
    end

    test "the target must be connected", %{code: code, host_token: host_token} do
      {:ok, _, host} = join_host(code, host_token, "Hana")
      {:ok, %{player_id: sam}, sam_socket} = join_room(code, %{"display_name" => "Sam"})

      drop(code, sam_socket)

      # Handing the role to someone who has gone would leave the room hostless,
      # which is exactly what promotion exists to prevent.
      ref = push(host, "host_transfer", %{"player_id" => sam})
      assert_reply ref, :error, %{code: "not_connected"}

      ref = push(host, "host_transfer", %{"player_id" => "p_nobody"})
      assert_reply ref, :error, %{code: "not_connected"}

      ref = push(host, "host_transfer", %{})
      assert_reply ref, :error, %{code: "invalid_payload"}
    end
  end

  describe "promotion" do
    test "a host who disconnects is replaced by a player who is still there", %{
      code: code,
      host_token: host_token
    } do
      {:ok, _, host} = join_host(code, host_token, "Hana")
      {:ok, %{player_id: sam}, sam_socket} = join_room(code, %{"display_name" => "Sam"})

      drop(code, host)

      # The party carries on under Sam rather than waiting out a timeout.
      assert_push "state",
                  %{you: %{role: "host", player_id: ^sam, host_token: token}}
                  when is_binary(token)

      ref = push(sam_socket, "host_next", %{})
      assert_reply ref, :ok, %{}
    end

    test "the old host cannot reclaim the room after being replaced", %{
      code: code,
      host_token: host_token
    } do
      {:ok, _, host} = join_host(code, host_token, "Hana")
      {:ok, _, _} = join_room(code, %{"display_name" => "Sam"})

      drop(code, host)

      assert {:error, %{code: "invalid_token"}} = join_host(code, host_token)
    end

    test "with nobody else there the room keeps its host and waits", %{
      code: code,
      host_token: host_token
    } do
      {:ok, _, host} = join_host(code, host_token, "Hana")
      [{room, _}] = Registry.lookup(Fazoura.Rooms.Registry, code)

      drop(code, host)

      # Alone, so there is nobody to promote: the room stays up for the empty
      # grace period, which is what lets a lone host survive a blip.
      assert Process.alive?(room)
      assert {:ok, %{role: "host"}, _} = join_host(code, host_token)
    end
  end

  describe "host_close" do
    test "ends the room for everyone at once", %{code: code, host_token: host_token} do
      {:ok, _, host} = join_host(code, host_token, "Hana")
      {:ok, _, _sam} = join_room(code, %{"display_name" => "Sam"})
      [{room, _}] = Registry.lookup(Fazoura.Rooms.Registry, code)
      room_ref = Process.monitor(room)

      ref = push(host, "host_close", %{})
      assert_reply ref, :ok, %{}

      assert_push "room_closed", %{reason: "closed"}
      assert_receive {:DOWN, ^room_ref, :process, ^room, :normal}
      assert {:error, %{code: "room_not_found"}} = join_room(code, %{"display_name" => "Late"})
    end

    test "only the host may close the room", %{code: code, host_token: host_token} do
      # The host has to be present, or Sam would be promoted into the role and
      # closing the room would be his to do.
      {:ok, _, _host} = join_host(code, host_token, "Hana")
      {:ok, _, sam} = join_room(code, %{"display_name" => "Sam"})

      ref = push(sam, "host_close", %{})
      assert_reply ref, :error, %{code: "not_host"}
    end
  end
end

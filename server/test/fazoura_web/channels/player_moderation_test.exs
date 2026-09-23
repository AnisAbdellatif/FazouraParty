defmodule FazouraWeb.PlayerModerationTest do
  @moduledoc """
  Removing, reporting and banning players (PROTOCOL.md §3.5, §4.2), through the channel
  and the HTTP route a client uses.
  """

  use FazouraWeb.ConnCase, async: false

  import Phoenix.ChannelTest, except: [push: 3]
  require Phoenix.ChannelTest

  alias Fazoura.{Moderation, QuizFixtures, Quizzes, Rooms}
  alias Fazoura.Moderation.PlayerReport

  @endpoint FazouraWeb.Endpoint
  @reporter "reporter-key-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"

  # Joins from a stand-in connection process with the moderation a socket would carry.
  defp join_as(code, payload, meta) do
    test = self()

    spawn_link(fn ->
      send(test, {:joined, Rooms.join(code, self(), payload, meta)})
      Process.sleep(:infinity)
    end)

    assert_receive {:joined, result}
    result
  end

  defp listed_room do
    quiz = QuizFixtures.published!(%{"title" => "Public Night"})
    {:ok, code, host_token} = Rooms.create(Quizzes.to_pack(quiz), listed: true)
    {code, host_token}
  end

  test "a removed player is told so, and their token no longer lets them back" do
    {:ok, code, host_token} = Rooms.create(QuizFixtures.pack())
    {:ok, _, host} = join_room(code, %{"host_token" => host_token})

    {:ok, %{player_id: id, player_token: token}, player} =
      join_room(code, %{"display_name" => "Troll"})

    Process.unlink(player.channel_pid)
    ref = Phoenix.ChannelTest.push(host, "host_remove_player", %{"player_id" => id})
    assert_reply ref, :ok

    assert_push "room_closed", %{reason: "removed"}
    assert {:error, %{code: "invalid_token"}} = join_room(code, %{"player_token" => token})
    assert {:ok, _, _} = join_room(code, %{"display_name" => "Somebody"})
  end

  test "a banned connection is kept out of public rooms, not rooms joined by code" do
    {code, _host_token} = listed_room()
    {:ok, private, _} = Rooms.create(QuizFixtures.pack())
    banned = %{ip_hash: "hash-1", banned?: true}

    assert join_as(code, %{"display_name" => "Troll"}, banned) == {:error, :banned}
    assert {:ok, _, _} = join_as(private, %{"display_name" => "Troll"}, banned)
  end

  test "a banned host cannot put a room on the list" do
    {:ok, code, host_token} = Rooms.create(%Fazoura.Game.Pack{titles: [], questions: []})
    test = self()

    spawn_link(fn ->
      {:ok, _, _} =
        Rooms.join(code, self(), %{"host_token" => host_token}, %{banned?: true, ip_hash: "h"})

      send(test, {:listed, Rooms.intent(code, self(), {:set_listed, %{"listed" => true}})})
      Process.sleep(:infinity)
    end)

    assert_receive {:listed, {:error, :banned}}
  end

  test "a report about a player keeps their name, their answer and their address hash", %{
    conn: conn
  } do
    {code, host_token} = listed_room()

    {:ok, %{player_id: id}, _} =
      join_as(code, %{"display_name" => "Troll"}, %{ip_hash: "hash-9", banned?: false})

    assert conn
           |> put_req_header("x-host-token", host_token)
           |> put_req_header("x-owner-key", @reporter)
           |> post(~p"/api/rooms/#{code}/report", %{
             "player_id" => id,
             "reason" => "hate",
             "note" => "Their name."
           })
           |> response(204)

    assert [%PlayerReport{player_name: "Troll", ip_hash: "hash-9", note: "Their name."}] =
             Moderation.open_player_reports()

    # Without a token from the room, it is a room nobody has heard of.
    assert build_conn()
           |> put_req_header("x-owner-key", @reporter)
           |> post(~p"/api/rooms/#{code}/report", %{"player_id" => id, "reason" => "hate"})
           |> json_response(404)
  end

  test "an admin can end a room" do
    {:ok, code, _} = Rooms.create(QuizFixtures.pack())
    {:ok, _, socket} = join_room(code, %{"display_name" => "Sam"})
    Process.unlink(socket.channel_pid)

    assert Rooms.close(code) == :ok
    assert_push "room_closed", %{reason: "closed"}
  end
end

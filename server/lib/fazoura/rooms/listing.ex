defmodule Fazoura.Rooms.Listing do
  @moduledoc """
  The public room list (PROTOCOL.md §3.5).

  Each room keeps its own entry as its value in `Fazoura.Rooms.Registry`, updated after
  every change, so reading the list calls no room process — `GET /api/rooms` needs no
  token and is polled by every open list screen. A room that is not listed keeps `nil`
  there.

  No names, the host's included: the list is read by strangers, and a quiz title is the
  only text on it a person has reviewed.
  """

  alias Fazoura.Game

  @registry Fazoura.Rooms.Registry

  # The list is for picking a room, not for browsing every game on the node.
  @max_listed 50

  @doc "Stores `game`'s entry. Must be called by the room's own process, which owns it."
  @spec publish(Game.t()) :: :ok
  def publish(%Game{} = game) do
    Registry.update_value(@registry, game.room_code, fn _ -> entry(game) end)
    :ok
  end

  @doc "What the list shows for `game`, or nil when it is not listed."
  @spec entry(Game.t()) :: map() | nil
  def entry(%Game{listed: false}), do: nil

  def entry(%Game{} = game) do
    %{
      room_code: game.room_code,
      phase: Atom.to_string(game.phase),
      pack_titles: if(game.pack.questions == [], do: [], else: game.pack.titles),
      player_count: map_size(game.players),
      question_index: game.question_index,
      question_count: game.settings.question_count
    }
  end

  @doc """
  Every listed room: rooms waiting to start first, then the busiest. Full rooms are left
  out — there is nothing to join.
  """
  @spec all() :: [map()]
  def all do
    @registry
    |> Registry.select([{{:_, :_, :"$1"}, [{:"/=", :"$1", nil}], [:"$1"]}])
    |> Enum.reject(&(&1.player_count >= Game.max_players()))
    |> Enum.sort_by(&{&1.phase != "lobby", -&1.player_count, &1.room_code})
    |> Enum.take(@max_listed)
  end
end

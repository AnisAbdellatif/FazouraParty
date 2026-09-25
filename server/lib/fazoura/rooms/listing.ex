defmodule Fazoura.Rooms.Listing do
  @moduledoc """
  The public room list (PROTOCOL.md §3.5).

  Each room keeps its own entry as its value in `Fazoura.Rooms.Registry`, updated after
  every change, so reading the list calls no room process — `GET /api/rooms` needs no
  token and is polled by every open list screen. A room that is not listed keeps a `nil`
  entry there.

  No names, the host's included: the list is read by strangers, and a quiz title is the
  only text on it a person has reviewed.

  Beside the entry, every room — listed or not — records which stored quizzes it is
  playing, for `in_play?/1`. That is never part of the list: a quiz id is what fetches a
  quiz's answers.
  """

  alias Fazoura.Game

  @registry Fazoura.Rooms.Registry

  # The list is for picking a room, not for browsing every game on the node.
  @max_listed 50

  @doc "Stores `game`'s entry. Must be called by the room's own process, which owns it."
  @spec publish(Game.t()) :: :ok
  def publish(%Game{} = game) do
    Registry.update_value(@registry, game.room_code, fn _ -> value(game) end)
    :ok
  end

  # What the room keeps in the registry: its public entry (nil when it is not listed)
  # and the stored quizzes it is playing, which every room records — listed or not.
  defp value(game), do: %{listing: entry(game), quiz_ids: quiz_ids(game)}

  @doc "What the list shows for `game`, or nil when it is not listed."
  @spec entry(Game.t()) :: map() | nil
  def entry(%Game{listed: false}), do: nil

  def entry(%Game{} = game) do
    %{
      room_code: game.room_code,
      phase: Atom.to_string(game.phase),
      pack_titles: if(game.pack.questions == [], do: [], else: game.pack.titles),
      player_count: map_size(game.players),
      room_size: game.room_size,
      question_index: game.question_index,
      question_count: game.settings.question_count
    }
  end

  defp quiz_ids(%Game{phase: :finished}), do: []

  defp quiz_ids(%Game{pack: pack}),
    do: for(%{quiz_id: id} <- pack.questions, is_binary(id), uniq: true, do: id)

  @doc """
  Whether any room is playing `quiz_id` right now — public or private.

  Everyone in a room sees the quiz's title, and a title finds the quiz. Its answers can
  be downloaded for offline play, so while a room has it chosen or under way that
  download waits: otherwise anybody in the room could play with every answer in hand.
  A private room is no different, since the players in it need not know each other
  either.
  """
  @spec in_play?(String.t()) :: boolean()
  def in_play?(quiz_id) do
    @registry
    |> Registry.select([{{:_, :_, :"$1"}, [{:is_map, :"$1"}], [:"$1"]}])
    |> Enum.any?(&(quiz_id in &1.quiz_ids))
  end

  @doc """
  Every listed room: rooms waiting to start first, then the busiest. Full rooms are left
  out — there is nothing to join.
  """
  @spec all() :: [map()]
  def all do
    @registry
    |> Registry.select([{{:_, :_, :"$1"}, [{:is_map, :"$1"}], [:"$1"]}])
    |> Enum.map(& &1.listing)
    |> Enum.reject(&(is_nil(&1) or &1.player_count >= &1.room_size))
    |> Enum.sort_by(&{&1.phase != "lobby", -&1.player_count, &1.room_code})
    |> Enum.take(@max_listed)
  end
end

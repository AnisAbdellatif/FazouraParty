defmodule Fazoura.Rooms.Selection do
  @moduledoc """
  What a `host_select_quiz` payload becomes: the one pool of questions a round is drawn
  from (PROTOCOL.md §6.4).

  Entries may mix stored quizzes, by `quiz_id`, with documents sent inline. An inline
  quiz's photos go into `Fazoura.Rooms.Images` as it resolves, so a resolution that
  succeeds hands back their keys — the room attaches them to itself, or deletes them if
  the game then refuses the selection — and one that fails half way deletes the ones it
  had already stored, since no room will ever collect them.
  """

  alias Fazoura.Game
  alias Fazoura.Game.Pack
  alias Fazoura.Quizzes
  alias Fazoura.Rooms.Images

  # Most quizzes one round may draw from. A bound on how much a single room can be made
  # to hold, inline photos included.
  @max_quizzes 10

  @doc "This module's part of `protocol/fixtures/constants.json`."
  @spec constants() :: %{String.t() => term()}
  def constants, do: %{"max_quizzes" => @max_quizzes}

  @spec resolve(Game.t(), map()) :: {:ok, Pack.t(), [String.t()]} | {:error, atom()}
  def resolve(game, payload) do
    with :ok <- inline_allowed(game, payload), do: resolve_all(payload)
  end

  # A listed room refuses an inline quiz before decoding it: its photos would only be
  # thrown away again once the game said no (PROTOCOL.md §3.5).
  defp inline_allowed(%Game{listed: true}, %{"quizzes" => quizzes}) when is_list(quizzes) do
    if Enum.any?(quizzes, &match?(%{"quiz" => _}, &1)),
      do: {:error, :quiz_not_public},
      else: :ok
  end

  defp inline_allowed(_game, _payload), do: :ok

  # The accumulator carries the keys and the bytes spent so far: the keys so a failure
  # can clean up, and the bytes because the inline cap bounds the room rather than each
  # quiz in it.
  defp resolve_all(%{"quizzes" => quizzes})
       when is_list(quizzes) and quizzes != [] and length(quizzes) <= @max_quizzes do
    quizzes
    |> Enum.reduce_while({:ok, [], [], 0}, fn entry, {:ok, packs, keys, spent} ->
      case resolve_one(entry, spent) do
        {:ok, pack, image_keys, spent} ->
          {:cont, {:ok, [pack | packs], keys ++ image_keys, spent}}

        error ->
          {:halt, {error, keys}}
      end
    end)
    |> case do
      {:ok, packs, image_keys, _spent} ->
        {:ok, Pack.merge(Enum.reverse(packs)), image_keys}

      {error, orphans} ->
        Images.delete(orphans)
        error
    end
  end

  defp resolve_all(_payload), do: {:error, :invalid_quiz}

  defp resolve_one(%{"quiz_id" => id}, spent) when is_binary(id) do
    case Quizzes.fetch(id) do
      # A stored quiz's photos are on disk and served from there, so they cost the room
      # nothing to hold.
      {:ok, quiz} -> {:ok, Quizzes.to_pack(quiz), [], spent}
      _ -> {:error, :quiz_not_found}
    end
  end

  defp resolve_one(%{"quiz" => %{} = document}, spent) do
    case Quizzes.inline_pack(document, spent) do
      {:ok, pack, image_keys, spent} ->
        {:ok, pack, image_keys, spent}

      # Worth saying which: "too big" is something the host can act on.
      {:error, reason}
      when reason in [:quiz_too_large, :image_too_large, :unsupported_image, :too_many_rooms] ->
        {:error, reason}

      _ ->
        {:error, :invalid_quiz}
    end
  end

  defp resolve_one(_entry, _spent), do: {:error, :invalid_quiz}
end

defmodule Fazoura.Game.Pack do
  @moduledoc """
  Immutable snapshot of the questions a running room plays.

  Built from a stored quiz by `Fazoura.Quizzes.to_pack/1` (or `from_map/1` in tests), and
  from several of them by `merge/1` — a round is played from one pool drawn from every
  quiz the host selected (PROTOCOL.md §6.4). Rooms copy it at creation, so later edits can
  never affect a running game.
  """

  defmodule Question do
    @moduledoc false

    @enforce_keys [:id, :type, :prompt, :accepted_answers, :time_limit_ms]
    defstruct [
      :id,
      :type,
      :prompt,
      :accepted_answers,
      :time_limit_ms,
      # The stored quiz this question was snapshotted from, so a player who
      # sees something in a game can report it (QUIZ_FORMAT.md §5.9) without
      # anybody having to broadcast quiz ids — an id in a `state` would also be
      # a cheat button, since `GET /api/quizzes/:id/download` hands out the
      # accepted answers. `nil` for a private quiz sent inline: there is nothing
      # published to report.
      quiz_id: nil,
      image_url: nil,
      difficulty: "easy"
    ]

    @type t :: %__MODULE__{
            id: String.t(),
            type: String.t(),
            prompt: String.t(),
            accepted_answers: [String.t()],
            time_limit_ms: pos_integer(),
            quiz_id: String.t() | nil,
            image_url: String.t() | nil,
            difficulty: String.t()
          }
  end

  @enforce_keys [:titles, :questions]
  defstruct [
    :questions,
    # Titles of the selected quizzes, in the order the host chose them. Empty
    # means nothing is selected yet (PROTOCOL.md §5.1, §6.4).
    titles: [],
    # Suggested room settings, from the first quiz selected (QUIZ_FORMAT.md §2.1).
    default_time_limit_ms: nil,
    default_difficulty_multiplier: false
  ]

  @type t :: %__MODULE__{
          titles: [String.t()],
          questions: [Question.t()],
          default_time_limit_ms: pos_integer() | nil,
          default_difficulty_multiplier: boolean()
        }

  @default_time_limit_ms 30_000

  @doc """
  One pool from the quizzes the host selected, in the order they selected them
  (PROTOCOL.md §6.4).

  Question ids are rewritten to stay unique across the pool: two quizzes may each call a
  question `q1`, and clients use the id to tell one question from the next. Ids are opaque
  (§1), so rewriting them is ours to do. Lobby defaults come from the first quiz, because a
  pool has none of its own.
  """
  @spec merge([t()]) :: t()
  def merge([pack]), do: pack

  def merge([first | _] = packs) do
    %__MODULE__{
      titles: Enum.flat_map(packs, & &1.titles),
      default_time_limit_ms: first.default_time_limit_ms,
      default_difficulty_multiplier: first.default_difficulty_multiplier,
      questions:
        packs
        |> Enum.with_index()
        |> Enum.flat_map(fn {pack, index} ->
          Enum.map(pack.questions, &%{&1 | id: "#{index}-#{&1.id}"})
        end)
    }
  end

  @spec from_map(map()) :: t()
  def from_map(%{"title" => title, "questions" => questions}) do
    %__MODULE__{
      titles: [title],
      questions: Enum.map(questions, &question_from_map/1)
    }
  end

  defp question_from_map(map) do
    %Question{
      id: Map.fetch!(map, "id"),
      type: Map.get(map, "type", "text"),
      prompt: Map.fetch!(map, "prompt"),
      accepted_answers: Map.fetch!(map, "accepted_answers"),
      time_limit_ms: Map.get(map, "time_limit_ms", @default_time_limit_ms),
      image_url: Map.get(map, "image_url"),
      difficulty: difficulty!(Map.get(map, "difficulty", "easy"))
    }
  end

  @difficulties ~w(easy medium hard)

  defp difficulty!(value) when value in @difficulties, do: value

  defp difficulty!(value),
    do: raise(ArgumentError, "unknown difficulty #{inspect(value)}; use easy, medium or hard")
end

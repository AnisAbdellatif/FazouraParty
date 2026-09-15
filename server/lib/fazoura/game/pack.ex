defmodule Fazoura.Game.Pack do
  @moduledoc """
  Immutable pack snapshot used by a running room.

  Phase 1 loads built-in packs from `priv/packs/<id>.json`. Rooms copy the pack at
  creation, so later edits can never affect a running game.
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
      image_url: nil,
      difficulty: "easy"
    ]

    @type t :: %__MODULE__{
            id: String.t(),
            type: String.t(),
            prompt: String.t(),
            accepted_answers: [String.t()],
            time_limit_ms: pos_integer(),
            image_url: String.t() | nil,
            difficulty: String.t()
          }
  end

  @enforce_keys [:id, :title, :questions]
  defstruct [:id, :title, :questions]

  @type t :: %__MODULE__{id: String.t(), title: String.t(), questions: [Question.t()]}

  @default_time_limit_ms 30_000

  @spec fetch(term()) :: {:ok, t()} | {:error, :pack_not_found}
  def fetch(id) when is_binary(id) do
    with true <- id =~ ~r/\A[a-z0-9-]{1,64}\z/,
         {:ok, json} <- File.read(Path.join([:code.priv_dir(:fazoura), "packs", id <> ".json"])) do
      {:ok, json |> Jason.decode!() |> Map.put("id", id) |> from_map()}
    else
      _ -> {:error, :pack_not_found}
    end
  end

  def fetch(_id), do: {:error, :pack_not_found}

  @spec from_map(map()) :: t()
  def from_map(%{"title" => title, "questions" => questions} = map) do
    %__MODULE__{
      id: Map.get(map, "id", "inline"),
      title: title,
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

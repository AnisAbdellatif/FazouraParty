defmodule Fazoura.Quizzes.Tag do
  @moduledoc """
  One tag on a quiz (protocol/QUIZ_FORMAT.md §2.3).

  Tags are free text: the suggested ones clients offer are a starting point, not a closed
  list, so any short non-blank string is accepted. Everything is normalised (lower case,
  collapsed whitespace) so "Pop  Culture" and "pop culture" are the same tag.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @max_length 24

  schema "quiz_tags" do
    field :tag, :string
    field :position, :integer

    belongs_to :quiz, Fazoura.Quizzes.Quiz

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @type t :: %__MODULE__{}

  @spec max_length() :: pos_integer()
  def max_length, do: @max_length

  @doc ~S(Lower cased and trimmed, inner whitespace collapsed; anything else becomes "".)
  @spec normalize(term()) :: String.t()
  def normalize(tag) when is_binary(tag) do
    tag |> String.downcase() |> String.replace(~r/\s+/u, " ") |> String.trim()
  end

  def normalize(_tag), do: ""

  @spec changeset(term(), pos_integer()) :: Ecto.Changeset.t()
  def changeset(tag, position) do
    %__MODULE__{}
    |> cast(%{"tag" => normalize(tag), "position" => position}, [:tag, :position])
    |> validate_required([:tag, :position])
    |> validate_length(:tag, min: 1, max: @max_length)
  end
end

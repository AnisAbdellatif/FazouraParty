defmodule Fazoura.Quizzes.Submission do
  @moduledoc """
  A quiz somebody has offered to the public library, waiting to be read
  (QUIZ_FORMAT.md §4).

  It is a `.fazoura` package and not a quiz, which is the whole point: nothing
  unreviewed reaches the `quizzes` table or the uploads volume, so every row in
  those means "published" with no second condition a query can forget. Approving
  unpacks the package through the same path a preset takes, and only then does a
  quiz exist.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Fazoura.Quizzes.Quiz

  @statuses ~w(pending rejected approved)

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "quiz_submissions" do
    field :package, :binary
    field :title, :string
    field :question_count, :integer, default: 0
    field :has_photos, :boolean, default: false
    field :owner_key_hash, :string
    field :status, :string, default: "pending"
    field :review_note, :string
    field :submitted_at, :utc_datetime_usec
    field :reviewed_at, :utc_datetime

    belongs_to :quiz, Quiz

    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{}

  def statuses, do: @statuses

  @doc "A new submission. `document` is the manifest already read out of `package`."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(submission, params) do
    submission
    |> cast(params, [:package, :title, :question_count, :has_photos, :owner_key_hash])
    |> validate_required([:package, :title, :owner_key_hash])
    |> validate_length(:title, min: 1, max: 80)
    |> put_change(:status, "pending")
    |> put_change(:submitted_at, DateTime.utc_now())
  end
end

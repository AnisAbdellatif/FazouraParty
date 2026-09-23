defmodule Fazoura.Quizzes.Report do
  @moduledoc """
  Somebody saying a published quiz should not be public (QUIZ_FORMAT.md §5.9).

  The review queue reads a quiz before it goes out; this is the other direction
  — what got through, or what was fine until its author edited it. Google Play
  requires an in-app way to report user content and a timely answer, so a report
  is a queue item with a clock on it, not a mailbox nobody empties.

  A report is anonymous. The reporting device's key is hashed only so that one
  device tapping twice counts once: an admin reads "reported by 4" as four
  people, and that has to be true for the number to be worth anything.
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Fazoura.Quizzes.Quiz

  # What a reporter picks from. Deliberately short: a long list makes people
  # guess, and the note is where anything specific goes. These map onto the
  # categories Play's own policy is written in.
  @reasons ~w(sexual hate violence illegal spam other)
  @statuses ~w(open dismissed)

  @note_limit 500

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "quiz_reports" do
    field :reason, :string
    field :note, :string
    field :reporter_key_hash, :string
    field :status, :string, default: "open"
    field :reported_at, :utc_datetime_usec
    field :reviewed_at, :utc_datetime

    belongs_to :quiz, Quiz

    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{}

  @doc "Reasons a reporter may choose (QUIZ_FORMAT.md §5.9)."
  @spec reasons() :: [String.t()]
  def reasons, do: @reasons

  @spec statuses() :: [String.t()]
  def statuses, do: @statuses

  @doc "How a reason reads in the dashboard."
  @spec describe(String.t()) :: String.t()
  def describe("sexual"), do: "Sexual or adult content"
  def describe("hate"), do: "Hate speech or harassment"
  def describe("violence"), do: "Violence or dangerous content"
  def describe("illegal"), do: "Illegal content"
  def describe("spam"), do: "Spam or nonsense"
  def describe("other"), do: "Something else"
  def describe(other), do: other

  @doc "A new report."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(report, params) do
    report
    |> cast(params, [:quiz_id, :reason, :note, :reporter_key_hash])
    |> validate_required([:quiz_id, :reason, :reporter_key_hash])
    |> validate_inclusion(:reason, @reasons)
    # Trimmed to nothing is nothing, so an empty box does not become a note
    # that reads as blank in the queue.
    |> update_change(:note, &blank_to_nil/1)
    |> validate_length(:note, max: @note_limit)
    |> put_change(:status, "open")
    |> put_change(:reported_at, DateTime.utc_now())
    |> unique_constraint([:quiz_id, :reporter_key_hash])
    |> foreign_key_constraint(:quiz_id)
  end

  defp blank_to_nil(note) when is_binary(note) do
    case String.trim(note) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp blank_to_nil(note), do: note
end

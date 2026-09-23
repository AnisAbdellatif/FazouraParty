defmodule Fazoura.Repo.Migrations.CreateQuizReports do
  use Ecto.Migration

  @moduledoc """
  Somewhere for "this quiz should not be public" to land (QUIZ_FORMAT.md §5.9).

  Review catches what is wrong before a quiz is published; this catches what got
  through, or what was fine until its author edited it. Google Play requires an
  in-app way to report user content and a timely answer to it, so these rows are
  a queue with a clock on them rather than a mailbox.
  """
  def change do
    create table(:quiz_reports, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # The reports go when the quiz does: taking it down is the answer, and a
      # report about a quiz nobody can find is not a queue item any more.
      add :quiz_id, references(:quizzes, type: :binary_id, on_delete: :delete_all), null: false

      add :reason, :string, null: false
      # What the reporter typed, if anything. Capped in the changeset.
      add :note, :text

      # sha256 of the reporting device's key — the same per-device secret a
      # publisher uses (§4), never an account. Here only so one device tapping
      # twice is one report: an admin reads the count as "how many people",
      # and it has to be true.
      add :reporter_key_hash, :string, null: false

      add :status, :string, null: false, default: "open"
      add :reviewed_at, :utc_datetime

      # Microseconds, like a submission's, because this orders the queue and
      # two reports a moment apart must not tie (the 24h clock starts here).
      add :reported_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime)
    end

    # The queue: open first, oldest first.
    create index(:quiz_reports, [:status, :reported_at])
    # Grouping a quiz's reports, and the count beside it.
    create index(:quiz_reports, [:quiz_id])
    # One device, one report per quiz. A second is that device changing its
    # mind about the wording, not a second voice.
    create unique_index(:quiz_reports, [:quiz_id, :reporter_key_hash])
  end
end

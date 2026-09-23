defmodule Fazoura.Repo.Migrations.CreateQuizSubmissions do
  use Ecto.Migration

  @moduledoc """
  Publishing became a submission, and a submission is a package rather than a
  quiz (QUIZ_FORMAT.md §4).

  Nothing unreviewed enters the `quizzes` table or the uploads volume: the
  device sends one `.fazoura` and it sits here as a blob until somebody has
  read it. Approving unpacks it through the same path a preset takes, which is
  what makes the `quizzes` table mean "public" again with no second condition
  for a query to forget.
  """
  def change do
    create table(:quiz_submissions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      # The whole `.fazoura`, photos included. Capped by Archive.max_bytes/0
      # before it is ever read, so this column cannot be used to fill the disk.
      add :package, :binary, null: false

      # Copied out of the document when it arrives, so the queue can be listed
      # without inflating every package to draw a table.
      add :title, :string, null: false
      add :question_count, :integer, null: false, default: 0
      add :has_photos, :boolean, null: false, default: false

      # Only this device may withdraw it or see why it was refused. Same
      # per-device key as a published quiz (§4) — not an account.
      add :owner_key_hash, :string, null: false

      add :status, :string, null: false, default: "pending"
      # Why it was turned down, shown to the device that sent it.
      add :review_note, :text
      # The quiz it became, so its author's device can follow it once it is live.
      add :quiz_id, references(:quizzes, type: :binary_id, on_delete: :nilify_all)

      # Microseconds, unlike the other timestamps here, because this one orders
      # the queue: at second resolution two submissions a moment apart tie and
      # "oldest first" falls back to a random uuid.
      add :submitted_at, :utc_datetime_usec, null: false
      add :reviewed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # The queue: pending first, oldest first.
    create index(:quiz_submissions, [:status, :submitted_at])
    # A device listing what it has sent.
    create index(:quiz_submissions, [:owner_key_hash])
  end
end

defmodule Fazoura.Repo.Migrations.CreateQuizTags do
  use Ecto.Migration

  # Tags replace the fixed category (QUIZ_FORMAT.md §2.3). A row per tag keeps
  # "quizzes with this tag" a plain indexed lookup on SQLite and Postgres alike,
  # which an array column can't do portably.
  def change do
    create table(:quiz_tags, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :quiz_id, references(:quizzes, type: :binary_id, on_delete: :delete_all), null: false

      add :tag, :string, null: false
      add :position, :integer, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:quiz_tags, [:quiz_id, :tag])
    create index(:quiz_tags, [:tag])

    alter table(:quizzes) do
      remove :category, :string, null: false, default: "general"
      remove :tags, {:array, :string}, null: false
    end
  end
end

defmodule Fazoura.Repo.Migrations.CreateQuizzes do
  use Ecto.Migration

  # Portable across SQLite (dev/test) and Postgres (prod): string enums, no
  # Postgres-only SQL, and no defaults on array columns (set in changesets).
  def change do
    create table(:quizzes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :slug, :string
      add :format_version, :integer, null: false, default: 1
      add :title, :string, null: false
      add :description, :text
      add :language, :string, null: false, default: "en"
      add :category, :string, null: false, default: "general"
      add :tags, {:array, :string}, null: false
      add :source, :string, null: false
      add :visibility, :string, null: false
      add :owner_key_hash, :string
      add :default_time_limit_ms, :integer, null: false, default: 30_000
      add :default_difficulty_multiplier, :boolean, null: false, default: false
      add :question_count, :integer, null: false, default: 0
      add :has_photos, :boolean, null: false, default: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:quizzes, [:slug])
    create index(:quizzes, [:visibility, :updated_at])
    create index(:quizzes, [:owner_key_hash])

    create table(:quiz_questions, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :quiz_id, references(:quizzes, type: :binary_id, on_delete: :delete_all), null: false

      add :position, :integer, null: false
      add :type, :string, null: false
      add :prompt, :text, null: false
      add :accepted_answers, {:array, :string}, null: false
      add :difficulty, :string, null: false, default: "easy"
      add :time_limit_ms, :integer
      add :image_key, :string
      add :image_alt, :string
      add :explanation, :text

      timestamps(type: :utc_datetime)
    end

    create unique_index(:quiz_questions, [:quiz_id, :position])

    create table(:images, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :key, :string, null: false
      add :content_type, :string, null: false
      add :byte_size, :integer, null: false
      add :owner_key_hash, :string, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create unique_index(:images, [:key])
  end
end

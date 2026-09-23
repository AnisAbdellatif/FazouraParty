defmodule Fazoura.Repo.Migrations.VersionQuizzesByNumber do
  use Ecto.Migration

  import Ecto.Query

  @moduledoc """
  Swaps the two quiz version schemes so each says what it is (QUIZ_FORMAT.md §2.1).

  `format_version` was an integer and is now `<major>.<minor>`: the format is a
  contract, and a document that uses a field added later is readable by an older
  reader exactly when the major still matches. That is the distinction an
  integer could not make.

  A quiz's own `version` was `<major>.<minor>` and is now a plain integer. It was
  never a contract — it is a revision counter, bumped every time a published quiz
  is replaced, and clients compare it to spot a stale offline copy. The major was
  always 1 and never meant anything.

  Columns are added, backfilled and renamed rather than altered in place, because
  SQLite cannot change a column's type and this migration has to run on both it
  and Postgres (AGENTS.md §5).
  """

  def up do
    alter table(:quizzes) do
      add :format_version_new, :string, null: false, default: "1.0"
      add :version_new, :integer, null: false, default: 1
    end

    flush()

    for %{id: id, version: version} <-
          repo().all(from(q in "quizzes", select: %{id: q.id, version: q.version})) do
      repo().update_all(from(q in "quizzes", where: q.id == ^id),
        set: [version_new: revision(version)]
      )
    end

    alter table(:quizzes) do
      remove :format_version
      remove :version
    end

    rename table(:quizzes), :format_version_new, to: :format_version
    rename table(:quizzes), :version_new, to: :version
  end

  def down do
    alter table(:quizzes) do
      add :format_version_old, :integer, null: false, default: 1
      add :version_old, :string, null: false, default: "1.0"
    end

    flush()

    for %{id: id, version: version} <-
          repo().all(from(q in "quizzes", select: %{id: q.id, version: q.version})) do
      repo().update_all(from(q in "quizzes", where: q.id == ^id),
        set: [version_old: "1.#{max(version - 1, 0)}"]
      )
    end

    alter table(:quizzes) do
      remove :format_version
      remove :version
    end

    rename table(:quizzes), :format_version_old, to: :format_version
    rename table(:quizzes), :version_old, to: :version
  end

  # "1.0" was the first revision, "1.1" the second. The counter is how many
  # revisions there have been, so it starts at 1 rather than 0.
  defp revision(version) when is_binary(version) do
    case String.split(version, ".", parts: 2) do
      [_major, minor] ->
        case Integer.parse(minor) do
          {n, _rest} -> n + 1
          :error -> 1
        end

      _other ->
        1
    end
  end

  defp revision(_version), do: 1
end

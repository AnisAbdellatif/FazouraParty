defmodule Fazoura.Release do
  @moduledoc """
  Database tasks for a built release, where Mix is not available.

      bin/fazoura eval "Fazoura.Release.setup()"

  The deploy job runs this with the new image before the old container stops.
  """

  @app :fazoura

  @doc "Migrates, then syncs the built-in quizzes. What a deploy runs."
  @spec setup() :: :ok
  def setup do
    migrate()
    seed()
  end

  @spec migrate() :: :ok
  def migrate do
    load()

    for repo <- repos() do
      {:ok, _result, _apps} =
        Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end

    :ok
  end

  @doc "Rolls `repo` back to `version`. Manual recovery only."
  @spec rollback(module(), integer()) :: :ok
  def rollback(repo, version) do
    load()

    {:ok, _result, _apps} =
      Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))

    :ok
  end

  @doc """
  Upserts `priv/quizzes/*.json` and every `.fazoura` package in the packages directory.
  Idempotent, so every deploy may run it.
  """
  @spec seed() :: :ok
  def seed do
    load()

    for repo <- repos() do
      {:ok, _result, _apps} =
        Ecto.Migrator.with_repo(repo, fn _repo ->
          Fazoura.Quizzes.sync_builtin!()
          Fazoura.Quizzes.sync_packages!()
        end)
    end

    :ok
  end

  defp repos, do: Application.fetch_env!(@app, :ecto_repos)

  defp load, do: Application.load(@app)
end

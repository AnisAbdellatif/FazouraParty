defmodule Fazoura.Repo.Migrations.CreateAppSettings do
  use Ecto.Migration

  # Settings an admin edits at runtime, as JSON text so new ones need no migration.
  def change do
    create table(:app_settings, primary_key: false) do
      add :key, :string, primary_key: true
      add :value, :text, null: false

      timestamps(type: :utc_datetime)
    end
  end
end

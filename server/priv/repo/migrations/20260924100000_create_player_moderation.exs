defmodule Fazoura.Repo.Migrations.CreatePlayerModeration do
  use Ecto.Migration

  @moduledoc """
  Reports about a player, and bans from public rooms (PROTOCOL.md §3.5).

  Players have no accounts, so a report is about a name in a room, and what it keeps
  is what was on the screen — the name and the answer — plus a keyed hash of the
  connection's address (`Fazoura.Moderation.IpHash`), which is all a ban can hold on
  to. Every one of these is forgotten within 90 days (`Fazoura.Moderation.Sweeper`).
  """
  def change do
    create table(:player_reports, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :room_code, :string, null: false
      add :player_name, :string, null: false
      # The reported player's answer to the question on screen, if they gave one.
      add :answer, :string
      add :reason, :string, null: false
      add :note, :text
      # Same meaning as on quiz reports: one device, one report per player.
      add :reporter_key_hash, :string, null: false
      # Erased after 90 days even while the report is still open.
      add :ip_hash, :string
      add :status, :string, null: false, default: "open"
      add :reviewed_at, :utc_datetime
      add :reported_at, :utc_datetime_usec, null: false

      timestamps(type: :utc_datetime)
    end

    create index(:player_reports, [:status, :reported_at])
    create unique_index(:player_reports, [:room_code, :player_name, :reporter_key_hash])

    create table(:public_room_bans, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :ip_hash, :string, null: false
      add :expires_at, :utc_datetime, null: false
      add :player_report_id, references(:player_reports, type: :binary_id, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    create index(:public_room_bans, [:ip_hash, :expires_at])
  end
end

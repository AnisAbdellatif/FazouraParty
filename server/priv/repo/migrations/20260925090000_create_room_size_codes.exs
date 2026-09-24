defmodule Fazoura.Repo.Migrations.CreateRoomSizeCodes do
  use Ecto.Migration

  @moduledoc """
  Codes an admin hands out to let a room hold more than the usual number of players
  (PROTOCOL.md §6.5). Only a hash of each code is kept: the admin sees the code once,
  when it is made, and `hint` — its last four characters — is how the list tells them
  apart afterwards.
  """
  def change do
    create table(:room_size_codes, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :code_hash, :string, null: false
      add :hint, :string, null: false
      # Who it was made for, in the admin's words.
      add :label, :string, null: false
      add :room_size, :integer, null: false
      # How many rooms it may unlock, and how many it has.
      add :max_rooms, :integer, null: false
      add :rooms_used, :integer, null: false, default: 0
      add :expires_at, :utc_datetime
      add :revoked_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:room_size_codes, [:code_hash])
  end
end

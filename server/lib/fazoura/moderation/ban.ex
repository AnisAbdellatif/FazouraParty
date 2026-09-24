defmodule Fazoura.Moderation.Ban do
  @moduledoc """
  A connection kept out of public rooms until `expires_at` (PROTOCOL.md §3.5), by the
  keyed hash of its address. Rooms joined by code are untouched: the people who
  gave somebody a code are the ones who decide whether they play.
  """

  use Ecto.Schema

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "public_room_bans" do
    field :ip_hash, :string
    field :expires_at, :utc_datetime
    belongs_to :player_report, Fazoura.Moderation.PlayerReport

    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{}
end

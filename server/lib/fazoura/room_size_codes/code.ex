defmodule Fazoura.RoomSizeCodes.Code do
  @moduledoc """
  One room size code (PROTOCOL.md §6.5): a room that redeems it may hold `room_size`
  players, and `max_rooms` rooms may redeem it before it is used up.
  """

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "room_size_codes" do
    field :code_hash, :string
    field :hint, :string
    field :label, :string
    field :room_size, :integer
    field :max_rooms, :integer
    field :rooms_used, :integer, default: 0
    field :expires_at, :utc_datetime
    field :revoked_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{}

  @doc "What an admin fills in. The hash and hint are the context's to set."
  def changeset(code, attrs, sizes) do
    code
    |> cast(attrs, [:label, :room_size, :max_rooms, :expires_at])
    |> update_change(:label, &String.trim/1)
    |> validate_required([:label, :room_size, :max_rooms])
    |> validate_length(:label, max: 80)
    |> validate_number(:room_size,
      greater_than_or_equal_to: sizes.first,
      less_than_or_equal_to: sizes.last
    )
    |> validate_number(:max_rooms, greater_than_or_equal_to: 1, less_than_or_equal_to: 10_000)
  end
end

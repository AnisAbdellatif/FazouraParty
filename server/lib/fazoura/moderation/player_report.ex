defmodule Fazoura.Moderation.PlayerReport do
  @moduledoc """
  Somebody saying a player's name or answer is not okay (PROTOCOL.md §3.5).

  There is no account to point at, so a report keeps what was on the screen — the
  name, and the answer if there was one — and the keyed hash of the player's address,
  which is what a ban can act on. Reasons are the quiz reports' (`Fazoura.Quizzes.Report`).
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Fazoura.Quizzes.Report

  @note_limit 500

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "player_reports" do
    field :room_code, :string
    field :player_name, :string
    field :answer, :string
    field :reason, :string
    field :note, :string
    field :reporter_key_hash, :string
    field :ip_hash, :string
    field :status, :string, default: "open"
    field :reported_at, :utc_datetime_usec
    field :reviewed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{}

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(report, params) do
    report
    |> cast(params, [
      :room_code,
      :player_name,
      :answer,
      :reason,
      :note,
      :reporter_key_hash,
      :ip_hash
    ])
    |> validate_required([:room_code, :player_name, :reason, :reporter_key_hash])
    |> validate_inclusion(:reason, Report.reasons())
    |> update_change(:note, &blank_to_nil/1)
    |> validate_length(:note, max: @note_limit)
    |> put_change(:status, "open")
    |> put_change(:reported_at, DateTime.utc_now())
    |> unique_constraint([:room_code, :player_name, :reporter_key_hash])
  end

  defp blank_to_nil(note) when is_binary(note) do
    case String.trim(note) do
      "" -> nil
      note -> note
    end
  end

  defp blank_to_nil(note), do: note
end

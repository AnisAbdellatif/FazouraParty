defmodule Fazoura.RoomSizeCodes do
  @moduledoc """
  Room size codes (PROTOCOL.md §6.5): made by an admin at `/admin/codes`, typed by a
  host in the lobby, and good for a set number of rooms until they expire or are
  revoked.

  Redeeming happens in the room's channel process, never in the room, which does not
  touch the database during play (AGENTS.md §4): the channel `find/2`s the code, asks the
  room whether its host may use it and whether it already has, `take/1`s one use, then
  asks the room to grow — and gives the use back with `refund/1` if that last step is
  refused.

  Only a SHA-256 of a code is stored. Twelve characters from the room-code alphabet
  are 60 bits, so a hash nobody salted is as good as a secret here, and a database
  that leaks gives away no working code.
  """

  import Ecto.Query

  alias Fazoura.{Game, Repo}
  alias Fazoura.RoomSizeCodes.Code

  # The largest room a code may grant. A 200-player room measured at about half of a
  # 4-vCPU server during a burst of answers (decisions.md, Snapshot Pacing).
  @max_room_size 200
  @alphabet ~c"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
  @length 12

  @doc "The room sizes a code may grant: more than a room holds anyway, up to the ceiling."
  @spec room_sizes() :: Range.t()
  def room_sizes, do: (Game.max_players() + 1)..@max_room_size

  @doc "Every code, newest first."
  @spec list() :: [Code.t()]
  def list, do: Repo.all(from c in Code, order_by: [desc: c.inserted_at, desc: c.id])

  @doc """
  Makes a code. Returns it in the clear alongside the record — the only time it is
  ever available — as `XXXX-XXXX-XXXX`.
  """
  @spec create(map()) :: {:ok, String.t(), Code.t()} | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    # The strong generator: a code is a capability, and `:rand` output can be
    # predicted from enough of it. 32 letters divide 256, so no letter is favoured.
    plain =
      for byte <- :binary.bin_to_list(:crypto.strong_rand_bytes(@length)), into: "" do
        <<Enum.at(@alphabet, rem(byte, length(@alphabet)))>>
      end

    changeset =
      %Code{code_hash: hash(plain), hint: String.slice(plain, -4, 4)}
      |> Code.changeset(attrs, room_sizes())

    with {:ok, code} <- Repo.insert(changeset), do: {:ok, format(plain), code}
  end

  @doc "Stops a code working. Rooms it already unlocked keep their size."
  @spec revoke(String.t(), DateTime.t()) :: :ok
  def revoke(id, now \\ DateTime.utc_now()) do
    from(c in Code, where: c.id == ^id and is_nil(c.revoked_at))
    |> Repo.update_all(set: [revoked_at: DateTime.truncate(now, :second)])

    :ok
  end

  @doc """
  The code `typed` names, if it is still in force — used up or not, which `take/1`
  decides. What a host types is taken loosely: case, spaces and dashes do not matter.
  """
  @spec find(term(), DateTime.t()) :: {:ok, Code.t()} | {:error, :invalid_code | :code_expired}
  def find(typed, now \\ DateTime.utc_now())

  def find(typed, now) when is_binary(typed) do
    code = Repo.get_by(Code, code_hash: hash(normalize(typed)))

    cond do
      # A revoked code reads as no code: the host has nothing to do about it but ask
      # whoever gave it to them.
      is_nil(code) or code.revoked_at != nil -> {:error, :invalid_code}
      expired?(code, now) -> {:error, :code_expired}
      true -> {:ok, code}
    end
  end

  def find(_typed, _now), do: {:error, :invalid_code}

  @doc """
  Counts one room against `code`, if it has one to spare — in one conditional UPDATE,
  so two rooms taking the last use at once cannot both have it.
  """
  @spec take(Code.t()) :: {:ok, Code.t()} | {:error, :code_used_up}
  def take(code) do
    {updated, _} =
      from(c in Code, where: c.id == ^code.id and c.rooms_used < c.max_rooms)
      |> Repo.update_all(inc: [rooms_used: 1])

    if updated == 1,
      do: {:ok, %{code | rooms_used: code.rooms_used + 1}},
      else: {:error, :code_used_up}
  end

  @doc "Gives back a use `take/1` counted for a room that did not take it."
  @spec refund(Code.t()) :: :ok
  def refund(%Code{id: id}) do
    from(c in Code, where: c.id == ^id and c.rooms_used > 0)
    |> Repo.update_all(inc: [rooms_used: -1])

    :ok
  end

  @doc "Whether a code can still unlock a room."
  @spec usable?(Code.t(), DateTime.t()) :: boolean()
  def usable?(code, now \\ DateTime.utc_now()) do
    is_nil(code.revoked_at) and code.rooms_used < code.max_rooms and not expired?(code, now)
  end

  defp expired?(%Code{expires_at: nil}, _now), do: false
  defp expired?(%Code{expires_at: at}, now), do: DateTime.compare(at, now) != :gt

  defp normalize(typed), do: typed |> String.upcase() |> String.replace(~r/[^A-Z0-9]/, "")

  defp hash(plain), do: :crypto.hash(:sha256, plain) |> Base.encode16(case: :lower)

  defp format(plain),
    do: plain |> String.graphemes() |> Enum.chunk_every(4) |> Enum.map_join("-", &Enum.join/1)
end

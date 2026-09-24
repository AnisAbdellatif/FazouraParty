defmodule Fazoura.RoomSizeCodesTest do
  use Fazoura.DataCase, async: false

  alias Fazoura.RoomSizeCodes
  alias Fazoura.RoomSizeCodes.Code

  defp code!(attrs \\ %{}) do
    {:ok, plain, code} =
      RoomSizeCodes.create(
        Map.merge(%{label: "Sunny School", room_size: 60, max_rooms: 2}, attrs)
      )

    {plain, code}
  end

  test "a code is shown once, as XXXX-XXXX-XXXX, and only its hash is kept" do
    {plain, code} = code!()

    assert plain =~ ~r/\A[A-Z2-9]{4}-[A-Z2-9]{4}-[A-Z2-9]{4}\z/
    assert code.hint == String.slice(plain, -4, 4)
    refute Repo.get!(Code, code.id).code_hash =~ String.replace(plain, "-", "")
  end

  test "the size must be more than a room holds anyway, and no more than the ceiling" do
    sizes = RoomSizeCodes.room_sizes()
    assert sizes.first == Fazoura.Game.max_players() + 1
    assert sizes.last == 200

    for size <- [sizes.first - 1, sizes.last + 1] do
      assert {:error, changeset} =
               RoomSizeCodes.create(%{label: "x", room_size: size, max_rooms: 1})

      assert changeset.errors[:room_size]
    end

    assert {:error, changeset} = RoomSizeCodes.create(%{label: " ", room_size: 60, max_rooms: 1})
    assert changeset.errors[:label]
  end

  test "it is found however the host types it, and unlocks as many rooms as it was made for" do
    {plain, code} = code!()
    loose = plain |> String.downcase() |> String.replace("-", " ")

    assert {:ok, %Code{room_size: 60} = found} = RoomSizeCodes.find(plain)
    assert {:ok, %Code{id: same}} = RoomSizeCodes.find(loose)
    assert same == found.id
    assert {:ok, _} = RoomSizeCodes.take(found)
    assert {:ok, _} = RoomSizeCodes.take(found)
    assert RoomSizeCodes.take(found) == {:error, :code_used_up}
    assert Repo.get!(Code, code.id).rooms_used == 2
  end

  test "a use given back can be used again" do
    {plain, code} = code!(%{max_rooms: 1})
    {:ok, found} = RoomSizeCodes.find(plain)
    assert {:ok, taken} = RoomSizeCodes.take(found)
    assert RoomSizeCodes.take(found) == {:error, :code_used_up}

    :ok = RoomSizeCodes.refund(taken)
    assert Repo.get!(Code, code.id).rooms_used == 0
    assert {:ok, _} = RoomSizeCodes.take(found)
  end

  test "an expired code says so; a revoked or unknown one is just not a code" do
    now = ~U[2026-09-24 12:00:00Z]
    {expiring, _} = code!(%{expires_at: ~U[2026-09-24 11:59:59Z]})
    {revoked, code} = code!()
    :ok = RoomSizeCodes.revoke(code.id, now)

    assert RoomSizeCodes.find(expiring, now) == {:error, :code_expired}
    assert RoomSizeCodes.find(revoked, now) == {:error, :invalid_code}
    assert RoomSizeCodes.find("NOPE-NOPE-NOPE", now) == {:error, :invalid_code}
    assert RoomSizeCodes.find(nil, now) == {:error, :invalid_code}
    refute RoomSizeCodes.usable?(Repo.get!(Code, code.id), now)
  end
end

defmodule FazouraWeb.RoomSizeTest do
  @moduledoc "Room size and room size codes through the channel (PROTOCOL.md §6.5)."

  # ConnCase for the database the channel reads codes from.
  use FazouraWeb.ConnCase, async: false

  import Phoenix.ChannelTest, except: [push: 3]
  require Phoenix.ChannelTest

  @endpoint FazouraWeb.Endpoint

  alias Fazoura.{QuizFixtures, Repo, Rooms, RoomSizeCodes}
  alias Fazoura.RoomSizeCodes.Code

  defp room do
    {:ok, code, host_token} = Rooms.create(QuizFixtures.pack())
    {:ok, _, host} = join_room(code, %{"host_token" => host_token})
    {code, host}
  end

  defp size_code!(max_rooms \\ 1) do
    {:ok, plain, code} =
      RoomSizeCodes.create(%{label: "Big party", room_size: 50, max_rooms: max_rooms})

    {plain, code}
  end

  defp uses(code), do: Repo.get!(Code, code.id).rooms_used

  test "every snapshot carries the room's size and limit" do
    {_code, _host} = room()
    assert_push "state", %{room_size: 32, room_size_limit: 32}
  end

  test "the host sets the room size, and a full room turns people away" do
    {code, host} = room()
    {:ok, _, _} = join_room(code, %{"display_name" => "Sam"})

    ref = Phoenix.ChannelTest.push(host, "host_set_room_size", %{"room_size" => 1})
    assert_reply ref, :ok
    assert {:error, %{code: "room_full"}} = join_room(code, %{"display_name" => "Kim"})

    ref = Phoenix.ChannelTest.push(host, "host_set_room_size", %{"room_size" => 0})
    assert_reply ref, :error, %{code: "invalid_room_size"}
  end

  test "a code raises the room to its size, and counts one room" do
    {code, host} = room()
    {plain, size_code} = size_code!()

    ref = Phoenix.ChannelTest.push(host, "host_redeem_size_code", %{"code" => plain})
    assert_reply ref, :ok
    assert_push "state", %{room_size: 50, room_size_limit: 50}
    assert uses(size_code) == 1

    # The same code again in the same room costs nothing.
    ref = Phoenix.ChannelTest.push(host, "host_redeem_size_code", %{"code" => plain})
    assert_reply ref, :ok
    assert uses(size_code) == 1

    # Used up for any other room.
    {_other, other_host} = room()
    ref = Phoenix.ChannelTest.push(other_host, "host_redeem_size_code", %{"code" => plain})
    assert_reply ref, :error, %{code: "code_used_up"}
    assert Rooms.intent(code, self(), :next) == {:error, :invalid_token}
  end

  test "a player can't redeem, and the use is given back" do
    {code, _host} = room()
    {:ok, _, player} = join_room(code, %{"display_name" => "Sam"})
    {plain, size_code} = size_code!()

    ref = Phoenix.ChannelTest.push(player, "host_redeem_size_code", %{"code" => plain})
    assert_reply ref, :error, %{code: "not_host"}
    assert uses(size_code) == 0
  end

  test "a wrong code is refused by what is wrong with it" do
    {_code, host} = room()

    ref = Phoenix.ChannelTest.push(host, "host_redeem_size_code", %{"code" => "NOPE-NOPE-NOPE"})
    assert_reply ref, :error, %{code: "invalid_code"}

    ref = Phoenix.ChannelTest.push(host, "host_redeem_size_code", %{})
    assert_reply ref, :error, %{code: "invalid_payload"}
  end
end

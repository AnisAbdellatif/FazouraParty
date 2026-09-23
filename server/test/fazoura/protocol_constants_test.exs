defmodule Fazoura.ProtocolConstantsTest do
  @moduledoc """
  The protocol's fixed numbers, held to `protocol/fixtures/constants.json` — the file the
  LAN host's constants are held to as well (app/test/core/protocol_constants_test.dart).
  """
  use ExUnit.Case, async: true

  alias Fazoura.{Game, ProtocolFixtures, Rooms}
  alias Fazoura.Rooms.{RoomServer, Selection}

  test "this implementation's constants are exactly the shared ones" do
    shared =
      "constants.json"
      |> ProtocolFixtures.load!()
      |> Map.reject(fn {key, _} -> String.starts_with?(key, "_") end)

    ours =
      Game.constants()
      |> Map.merge(RoomServer.constants())
      |> Map.merge(Selection.constants())
      |> Map.merge(Rooms.constants())

    assert ours == shared
  end
end

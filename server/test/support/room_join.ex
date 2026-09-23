defmodule FazouraWeb.RoomJoin do
  @moduledoc """
  Joining `room:<CODE>` the way a client does.

  Six test files had written this out, each having to remember that a join carries the
  protocol version and is refused before anything else is looked at (PROTOCOL.md §4.1) —
  so a version bump meant finding all six, and one of them aliasing `Game` differently
  was enough to hide a copy. `FazouraWeb.ChannelCase` imports this; the two suites that
  drive a channel from a `ConnCase` import it themselves.
  """

  @doc """
  Joins as a client would, stamping on the protocol version.

  `subscribe_and_join/4` rather than `join/4` because it is a superset: the test process
  is also subscribed to the room's topic, which `assert_push` does not care about and
  `assert_broadcast` needs.
  """
  defmacro join_room(code, payload) do
    quote do
      Phoenix.ChannelTest.socket(FazouraWeb.UserSocket, nil, %{})
      |> Phoenix.ChannelTest.subscribe_and_join(
        FazouraWeb.RoomChannel,
        "room:" <> unquote(code),
        Map.put(unquote(payload), "protocol_version", Fazoura.Game.protocol_major())
      )
    end
  end
end

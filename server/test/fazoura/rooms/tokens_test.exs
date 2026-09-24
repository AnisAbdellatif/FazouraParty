defmodule Fazoura.Rooms.TokensTest do
  use ExUnit.Case, async: true

  alias Fazoura.Rooms.Tokens

  test "a host token opens its own room in its own generation, and nothing else" do
    token = Tokens.host_token("ROOM42", 2)

    assert Tokens.host?(token, "ROOM42", 2)
    refute Tokens.host?(token, "ROOM42", 3), "the role has moved on"
    refute Tokens.host?(token, "OTHER1", 2)
    refute Tokens.host?("forged", "ROOM42", 2)
    refute Tokens.host?(nil, "ROOM42", 2)
  end

  test "a player token names its player, in its own room only" do
    token = Tokens.player_token("ROOM42", "p_sam")

    assert Tokens.player_id(token, "ROOM42") == {:ok, "p_sam"}
    assert Tokens.player_id(token, "OTHER1") == :error
    assert Tokens.player_id(Tokens.host_token("ROOM42"), "ROOM42") == :error
    assert Tokens.player_id(nil, "ROOM42") == :error
  end
end

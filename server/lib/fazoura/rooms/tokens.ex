defmodule Fazoura.Rooms.Tokens do
  @moduledoc """
  The two signed tokens a room issues (PROTOCOL.md §3.3), and the checks made on them.
  Each is signed for the room's `scope/1`, not merely its code.

  A **host token** names a room and a *generation*: the room bumps the generation every
  time the role changes hands (§3.4), so a token minted for an earlier holder stops
  verifying and a demoted host cannot take the room back. A **player token** names a
  room and a player id, and is what lets a player rejoin as themselves.

  Pure: no process, no room state. `Fazoura.Rooms.RoomServer` supplies the room's scope,
  the generation in force and whether a player id belongs to the room.
  """

  @endpoint FazouraWeb.Endpoint
  @max_age_s 86_400

  @doc """
  What a room's tokens are signed for: its code and a random value of its own.

  The code alone is not enough. Codes are reused once a room closes, and a token lives
  for a day, so a token from a room that has ended would otherwise open whichever room
  drew its code next — as host, at generation 0, for anybody who had created and
  abandoned rooms to collect them.
  """
  @spec scope(String.t()) :: String.t()
  def scope(code),
    do: code <> "/" <> Base.url_encode64(:crypto.strong_rand_bytes(12), padding: false)

  @spec host_token(String.t(), non_neg_integer()) :: String.t()
  def host_token(code, generation \\ 0),
    do: Phoenix.Token.sign(@endpoint, "host", {code, generation})

  @spec player_token(String.t(), String.t()) :: String.t()
  def player_token(code, player_id),
    do: Phoenix.Token.sign(@endpoint, "player", {code, player_id})

  @doc """
  Whether `token` is a host token for `code` in `generation` — the one in force. A token
  from before a transfer is as good as forged.
  """
  @spec host?(term(), String.t(), non_neg_integer()) :: boolean()
  def host?(token, code, generation) when is_binary(token) do
    match?({:ok, {^code, ^generation}}, verify(token, "host"))
  end

  def host?(_token, _code, _generation), do: false

  @doc """
  The player id a player token for `code` names, or `:error`. Whether that player is
  still in the room is the caller's question.
  """
  @spec player_id(term(), String.t()) :: {:ok, String.t()} | :error
  def player_id(token, code) when is_binary(token) do
    case verify(token, "player") do
      {:ok, {^code, id}} -> {:ok, id}
      _ -> :error
    end
  end

  def player_id(_token, _code), do: :error

  defp verify(token, salt), do: Phoenix.Token.verify(@endpoint, salt, token, max_age: @max_age_s)
end

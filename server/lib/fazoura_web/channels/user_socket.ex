defmodule FazouraWeb.UserSocket do
  use Phoenix.Socket

  alias Fazoura.Moderation.IpHash

  channel "room:*", FazouraWeb.RoomChannel

  # Guests are anonymous; identity is established per room on channel join (PROTOCOL.md §3.3).
  # The address is hashed on the spot and the hash is all the socket keeps: a room
  # stores it only against a report, and a ban matches on it (Fazoura.Moderation).
  @impl true
  def connect(_params, socket, connect_info) do
    ip_hash = connect_info |> FazouraWeb.ClientIp.from_connect_info() |> IpHash.hash()
    {:ok, assign(socket, :ip_hash, ip_hash)}
  end

  @impl true
  def id(_socket), do: nil
end

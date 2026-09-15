defmodule FazouraWeb.UserSocket do
  use Phoenix.Socket

  channel "room:*", FazouraWeb.RoomChannel

  # Guests are anonymous; identity is established per room on channel join (PROTOCOL.md §3.3).
  @impl true
  def connect(_params, socket, _connect_info), do: {:ok, socket}

  @impl true
  def id(_socket), do: nil
end

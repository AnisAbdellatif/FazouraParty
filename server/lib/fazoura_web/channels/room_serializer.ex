defmodule FazouraWeb.RoomSerializer do
  @moduledoc """
  Phoenix's V2 JSON serializer, handing each encoded message over as one binary.

  The channel process encodes; the socket process sends. Phoenix hands the JSON over as
  iodata — hundreds of small binaries for one snapshot — and every one of them is copied
  into the socket process's heap on the way, where it stays until that heap is collected.
  Measured on 250 rooms of 16, that left ~236 KB of garbage in every socket process,
  more than half of what a connected player costs. One binary is passed by reference
  instead of copied (decisions.md, Connection Memory).
  """

  @behaviour Phoenix.Socket.Serializer

  alias Phoenix.Socket.V2.JSONSerializer

  @impl true
  def fastlane!(broadcast), do: whole(JSONSerializer.fastlane!(broadcast))

  @impl true
  def encode!(message), do: whole(JSONSerializer.encode!(message))

  @impl true
  def decode!(raw, opts), do: JSONSerializer.decode!(raw, opts)

  defp whole({:socket_push, opcode, data}), do: {:socket_push, opcode, IO.iodata_to_binary(data)}
end

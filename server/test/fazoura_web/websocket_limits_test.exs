defmodule FazouraWeb.WebsocketLimitsTest do
  use ExUnit.Case, async: true

  alias FazouraWeb.RoomSerializer
  alias Phoenix.Socket.V2.JSONSerializer

  test "a frame fits the largest inline quiz the server will take" do
    # Base64 photos, and room for the document and the channel envelope around them.
    needed = div(Fazoura.Quizzes.max_inline_bytes() * 4, 3) + 1_000_000
    assert FazouraWeb.Endpoint.max_frame_size() >= needed

    [{"/socket", FazouraWeb.UserSocket, options}] =
      Enum.filter(FazouraWeb.Endpoint.__sockets__(), &(elem(&1, 0) == "/socket"))

    assert options[:websocket][:max_frame_size] == FazouraWeb.Endpoint.max_frame_size()
  end

  test "the room socket compresses what it sends, with the smaller deflate state" do
    [{"/socket", FazouraWeb.UserSocket, options}] =
      Enum.filter(FazouraWeb.Endpoint.__sockets__(), &(elem(&1, 0) == "/socket"))

    assert options[:websocket][:compress]

    http = Application.fetch_env!(:fazoura, FazouraWeb.Endpoint)[:http]
    assert http[:websocket_options][:deflate_options][:mem_level] == 4
  end

  test "the room socket hands each V2 message over as one binary" do
    [{"/socket", FazouraWeb.UserSocket, options}] =
      Enum.filter(FazouraWeb.Endpoint.__sockets__(), &(elem(&1, 0) == "/socket"))

    assert {RoomSerializer, "~> 2.0.0"} in options[:websocket][:serializer]

    message = %Phoenix.Socket.Message{
      join_ref: "1",
      ref: "2",
      topic: "room:K7QX2M",
      event: "state",
      payload: %{"players" => [%{"name" => "Sam", "score" => 10}]}
    }

    {:socket_push, :text, iodata} = JSONSerializer.encode!(message)
    assert {:socket_push, :text, binary} = RoomSerializer.encode!(message)
    assert is_binary(binary)
    assert binary == IO.iodata_to_binary(iodata)

    reply = %Phoenix.Socket.Reply{
      join_ref: "1",
      ref: "3",
      topic: "room:K7QX2M",
      status: :ok,
      payload: %{}
    }

    assert {:socket_push, :text, reply_binary} = RoomSerializer.encode!(reply)
    assert is_binary(reply_binary)

    raw = ~s(["1","4","room:K7QX2M","submit",{"answer":"Paris"}])

    assert RoomSerializer.decode!(raw, opcode: :text) ==
             JSONSerializer.decode!(raw, opcode: :text)
  end
end

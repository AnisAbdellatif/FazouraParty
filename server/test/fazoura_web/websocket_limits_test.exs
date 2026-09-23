defmodule FazouraWeb.WebsocketLimitsTest do
  use ExUnit.Case, async: true

  test "a frame fits the largest inline quiz the server will take" do
    # Base64 photos, and room for the document and the channel envelope around them.
    needed = div(Fazoura.Quizzes.max_inline_bytes() * 4, 3) + 1_000_000
    assert FazouraWeb.Endpoint.max_frame_size() >= needed

    [{"/socket", FazouraWeb.UserSocket, options}] =
      Enum.filter(FazouraWeb.Endpoint.__sockets__(), &(elem(&1, 0) == "/socket"))

    assert options[:websocket][:max_frame_size] == FazouraWeb.Endpoint.max_frame_size()
  end
end

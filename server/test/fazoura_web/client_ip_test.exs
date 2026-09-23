defmodule FazouraWeb.ClientIpTest do
  use ExUnit.Case, async: false

  alias FazouraWeb.ClientIp

  setup do
    previous = Application.get_env(:fazoura, :trust_forwarded_for)
    on_exit(fn -> Application.put_env(:fazoura, :trust_forwarded_for, previous) end)
  end

  @info %{
    peer_data: %{address: {127, 0, 0, 1}, port: 1234},
    x_headers: [{"x-forwarded-for", "6.6.6.6, 203.0.113.9"}]
  }

  test "behind our proxy, the address it appended — not what the client claimed" do
    Application.put_env(:fazoura, :trust_forwarded_for, true)
    assert ClientIp.from_connect_info(@info) == "203.0.113.9"
  end

  test "without a trusted proxy, the peer" do
    Application.put_env(:fazoura, :trust_forwarded_for, false)
    assert ClientIp.from_connect_info(@info) == "127.0.0.1"
    assert ClientIp.from_connect_info(%{}) == nil
  end
end

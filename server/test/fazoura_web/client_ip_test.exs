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

  test "an IPv6 address is collapsed to its /64, so one host can't rotate addresses" do
    Application.put_env(:fazoura, :trust_forwarded_for, false)

    peer = fn address -> ClientIp.from_connect_info(%{peer_data: %{address: address}}) end

    # Two addresses in the same /64 key to the same prefix; a v4-mapped address stays whole.
    assert peer.({0x2001, 0xDB8, 0, 0, 1, 2, 3, 4}) == "2001:db8::"
    assert peer.({0x2001, 0xDB8, 0, 0, 0xAAAA, 0xBBBB, 0xCCCC, 0xDDDD}) == "2001:db8::"
    assert peer.({0x2001, 0xDB8, 0, 1, 0, 0, 0, 0}) == "2001:db8:0:1::"
    assert peer.({0, 0, 0, 0, 0, 0xFFFF, 0x0102, 0x0304}) == "::ffff:1.2.3.4"
  end
end

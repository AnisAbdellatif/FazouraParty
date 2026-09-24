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

  test "an IPv6 address is its /64, so one subscriber is one caller" do
    Application.put_env(:fazoura, :trust_forwarded_for, true)

    one = fn address ->
      ClientIp.from_connect_info(%{x_headers: [{"x-forwarded-for", address}]})
    end

    assert one.("2001:db8:1:2:aaaa::1") == "2001:db8:1:2::/64"
    assert one.("2001:db8:1:2:ffff:ffff:ffff:ffff") == "2001:db8:1:2::/64"
    refute one.("2001:db8:1:3::1") == "2001:db8:1:2::/64"

    # From the socket's own peer as well as from the proxy's header.
    Application.put_env(:fazoura, :trust_forwarded_for, false)

    assert ClientIp.from_connect_info(%{peer_data: %{address: {0x2001, 0xDB8, 1, 2, 9, 9, 9, 9}}}) ==
             "2001:db8:1:2::/64"
  end

  test "IPv4 mapped into IPv6 is the IPv4 address" do
    Application.put_env(:fazoura, :trust_forwarded_for, true)

    assert ClientIp.from_connect_info(%{x_headers: [{"x-forwarded-for", "::ffff:203.0.113.9"}]}) ==
             "203.0.113.9"
  end
end

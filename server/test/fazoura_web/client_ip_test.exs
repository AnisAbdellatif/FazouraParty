defmodule FazouraWeb.ClientIpTest do
  use ExUnit.Case, async: false

  alias FazouraWeb.ClientIp

  setup do
    previous = Application.get_env(:fazoura, :proxy_hops)
    on_exit(fn -> Application.put_env(:fazoura, :proxy_hops, previous) end)
  end

  @info %{
    peer_data: %{address: {127, 0, 0, 1}, port: 1234},
    x_headers: [{"x-forwarded-for", "6.6.6.6, 203.0.113.9"}]
  }

  test "behind our proxy, the address it appended — not what the client claimed" do
    Application.put_env(:fazoura, :proxy_hops, 1)
    assert ClientIp.from_connect_info(@info) == "203.0.113.9"
  end

  test "behind two proxies, the address the outer one appended" do
    # Caddy appends the visitor, then kamal-proxy appends Caddy (deploy/deploy.yml).
    Application.put_env(:fazoura, :proxy_hops, 2)

    one = fn forwarded ->
      ClientIp.from_connect_info(%{x_headers: [{"x-forwarded-for", forwarded}]})
    end

    assert one.("203.0.113.9, 172.18.0.1") == "203.0.113.9"
    # Whatever the client sent comes before both, and is never the answer.
    assert one.("6.6.6.6, 203.0.113.9, 172.18.0.1") == "203.0.113.9"
    # Sent to kamal-proxy from the server itself: only it appended, and its entry is
    # the furthest peer our proxies saw.
    assert one.("172.18.0.1") == "172.18.0.1"
  end

  test "without a trusted proxy, the peer" do
    Application.put_env(:fazoura, :proxy_hops, 0)
    assert ClientIp.from_connect_info(@info) == "127.0.0.1"
    assert ClientIp.from_connect_info(%{}) == nil
  end

  test "an IPv6 address is its /64, so one subscriber is one caller" do
    Application.put_env(:fazoura, :proxy_hops, 1)

    one = fn address ->
      ClientIp.from_connect_info(%{x_headers: [{"x-forwarded-for", address}]})
    end

    assert one.("2001:db8:1:2:aaaa::1") == "2001:db8:1:2::/64"
    assert one.("2001:db8:1:2:ffff:ffff:ffff:ffff") == "2001:db8:1:2::/64"
    refute one.("2001:db8:1:3::1") == "2001:db8:1:2::/64"

    # From the socket's own peer as well as from the proxy's header.
    Application.put_env(:fazoura, :proxy_hops, 0)

    assert ClientIp.from_connect_info(%{peer_data: %{address: {0x2001, 0xDB8, 1, 2, 9, 9, 9, 9}}}) ==
             "2001:db8:1:2::/64"
  end

  test "IPv4 mapped into IPv6 is the IPv4 address" do
    Application.put_env(:fazoura, :proxy_hops, 1)

    assert ClientIp.from_connect_info(%{x_headers: [{"x-forwarded-for", "::ffff:203.0.113.9"}]}) ==
             "203.0.113.9"
  end
end

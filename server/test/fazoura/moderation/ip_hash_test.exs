defmodule Fazoura.Moderation.IpHashTest do
  @moduledoc """
  The one thing standing between "we moderate players" and "we keep a list of addresses".

  Every other test in the suite hands `ip_hash` a literal like `"hash-1"`, so nothing
  exercised the function that produces the real ones — and its claims are the ones the
  privacy policy makes: the same address is recognisable, the address cannot be read
  back, and a guess cannot be confirmed without the server's secret. The last is the
  only reason this is an HMAC rather than a plain digest: there are four billion IPv4
  addresses, so an unkeyed hash of one is a lookup table, not a protection.
  """

  use ExUnit.Case, async: true

  alias Fazoura.Moderation.IpHash

  @ip "203.0.113.9"

  test "the same address is always the same hash, and a different one is not" do
    assert IpHash.hash(@ip) == IpHash.hash(@ip)
    refute IpHash.hash(@ip) == IpHash.hash("203.0.113.10")

    # IPv6 and the loopback are addresses like any other, not special cases.
    refute IpHash.hash("::1") == IpHash.hash("127.0.0.1")
  end

  test "nothing about the address survives in the hash" do
    hash = IpHash.hash(@ip)

    assert hash =~ ~r/\A[0-9a-f]{64}\z/
    refute String.contains?(hash, @ip)
    refute String.contains?(hash, "203.0.113")
    refute String.contains?(hash, "113.9")

    # And it is a digest rather than an encoding: a long address and a short one come out
    # the same size, so the hash carries none of the input's length either.
    assert String.length(IpHash.hash("2001:db8:85a3::8a2e:370:7334")) == String.length(hash)
  end

  test "the hash is keyed, so holding it is not holding the address" do
    # This is the whole difference between a hash that protects an address and one that
    # only looks like it does: sha256("203.0.113.9") is computable by anybody.
    plain = :crypto.hash(:sha256, @ip) |> Base.encode16(case: :lower)

    refute IpHash.hash(@ip) == plain
  end

  test "an address we never learned hashes to nothing, rather than to a shared value" do
    # A socket with no address must not land every such player under one hash, which a
    # `hash("")` would: they would share bans and be counted as one device.
    assert IpHash.hash(nil) == nil
  end

  describe "what the socket keeps" do
    @describetag :socket

    test "a connection is remembered by its hash, never by its address" do
      {:ok, socket} =
        FazouraWeb.UserSocket.connect(%{}, Phoenix.Socket.__struct__(), %{
          peer_data: %{address: {203, 0, 113, 9}, port: 1234},
          x_headers: []
        })

      assert socket.assigns.ip_hash == IpHash.hash(@ip)
      refute socket.assigns.ip_hash == @ip
    end
  end
end

defmodule FazouraWeb.ClientIp do
  @moduledoc """
  Which address a request or a socket came from.

  Behind the host's Caddy the peer is always the proxy, so the address is the last
  `X-Forwarded-For` entry — the one our own proxy appended; anything before it is
  whatever the client chose to send. That is only believable because the app listens
  on loopback alone (AGENTS.md §6), which is what `TRUST_PROXY` asserts; with it off,
  the peer is the answer.

  Used by the rate limiter and by the room socket, so the two can never disagree about
  who somebody is.

  An IPv6 address answers as its /64 network (`2001:db8:1:2::/64`). One subscriber is
  normally handed a whole /64 and can use any address in it, so counting single
  addresses would give anybody with IPv6 a fresh identity per request — past every rate
  limit and every ban.
  """

  @spec from_conn(Plug.Conn.t()) :: String.t()
  def from_conn(conn) do
    forwarded = conn |> Plug.Conn.get_req_header("x-forwarded-for") |> last_forwarded()
    normalize((trust_forwarded?() && forwarded) || conn.remote_ip)
  end

  @doc "From a socket's `connect_info` (`:peer_data` and `:x_headers`), or nil without it."
  @spec from_connect_info(map()) :: String.t() | nil
  def from_connect_info(connect_info) do
    forwarded =
      for({"x-forwarded-for", value} <- Map.get(connect_info, :x_headers, []), do: value)
      |> last_forwarded()

    peer =
      case connect_info do
        %{peer_data: %{address: address}} -> address
        _ -> nil
      end

    normalize((trust_forwarded?() && forwarded) || peer)
  end

  defp last_forwarded(values) do
    values
    |> Enum.flat_map(&String.split(&1, ","))
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> List.last()
  end

  defp trust_forwarded?, do: Application.get_env(:fazoura, :trust_forwarded_for, false)

  defp normalize(nil), do: nil

  defp normalize(address) when is_binary(address) do
    case :inet.parse_address(String.to_charlist(address)) do
      {:ok, parsed} -> normalize(parsed)
      # Not an address: whatever the proxy wrote, as it wrote it.
      {:error, _reason} -> address
    end
  end

  # IPv4 mapped into IPv6 is the IPv4 address.
  defp normalize({0, 0, 0, 0, 0, 0xFFFF, high, low}),
    do: normalize({div(high, 256), rem(high, 256), div(low, 256), rem(low, 256)})

  defp normalize({a, b, c, d, _, _, _, _}),
    do: ntoa({a, b, c, d, 0, 0, 0, 0}) <> "/64"

  defp normalize(address), do: ntoa(address)

  defp ntoa(address), do: address |> :inet.ntoa() |> to_string()
end

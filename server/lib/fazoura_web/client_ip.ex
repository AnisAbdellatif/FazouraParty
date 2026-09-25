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
  """

  @spec from_conn(Plug.Conn.t()) :: String.t()
  def from_conn(conn) do
    forwarded = conn |> Plug.Conn.get_req_header("x-forwarded-for") |> last_forwarded()
    normalize((trust_forwarded?() && forwarded) || ntoa(conn.remote_ip))
  end

  @doc "From a socket's `connect_info` (`:peer_data` and `:x_headers`), or nil without it."
  @spec from_connect_info(map()) :: String.t() | nil
  def from_connect_info(connect_info) do
    forwarded =
      for({"x-forwarded-for", value} <- Map.get(connect_info, :x_headers, []), do: value)
      |> last_forwarded()

    peer =
      case connect_info do
        %{peer_data: %{address: address}} -> ntoa(address)
        _ -> nil
      end

    normalize((trust_forwarded?() && forwarded) || peer)
  end

  # One IPv6 host owns a whole /64 (often more), so keying a rate-limit bucket or a ban
  # hash on the exact address lets it rotate through billions of addresses to mint fresh
  # buckets and shed bans. Collapsing to the /64 prefix makes the aggregate — a home, a
  # phone — the unit, which is the unit an abuser actually controls. IPv4 (one address
  # per host) and a v4-mapped v6 address are left whole; anything unparsable is left as
  # it came, so behaviour is unchanged for the addresses we saw before.
  defp normalize(nil), do: nil

  defp normalize(address) when is_binary(address) do
    case :inet.parse_address(String.to_charlist(address)) do
      {:ok, {0, 0, 0, 0, 0, 0xFFFF, _, _}} -> address
      {:ok, {a, b, c, d, _, _, _, _}} -> ntoa({a, b, c, d, 0, 0, 0, 0})
      _ -> address
    end
  end

  defp last_forwarded(values) do
    values
    |> Enum.flat_map(&String.split(&1, ","))
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> List.last()
  end

  defp trust_forwarded?, do: Application.get_env(:fazoura, :trust_forwarded_for, false)

  defp ntoa(address), do: address |> :inet.ntoa() |> to_string()
end

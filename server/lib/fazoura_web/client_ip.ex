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
    (trust_forwarded?() && forwarded) || ntoa(conn.remote_ip)
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

    (trust_forwarded?() && forwarded) || peer
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

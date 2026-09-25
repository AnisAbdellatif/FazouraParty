defmodule FazouraWeb.Plugs.RateLimit do
  @moduledoc """
  Meters the endpoints that cost the server something (`Fazoura.RateLimit`).

      plug FazouraWeb.Plugs.RateLimit, bucket: :rooms, limit: 20, window_ms: 60_000

  Creating a room pins memory for ten minutes and uploading a photo writes to disk, and
  neither needs an account, so both are floodable by anyone who knows the URL. The limits
  are set well above a real party — a host creates a handful of rooms an evening — so
  hitting one means something is wrong.

  Callers are identified by IP, as `FazouraWeb.ClientIp` reads it: behind our proxies,
  the `X-Forwarded-For` entry the outermost of them appended (`:proxy_hops`, set in
  deploy/deploy.yml). With no hops configured the socket peer is used, so a
  direct-to-Phoenix deployment can't be spoofed by a header the client wrote.
  """

  @behaviour Plug

  import FazouraWeb.ApiHelpers, only: [error: 4]

  alias Fazoura.RateLimit

  @impl true
  def init(opts) do
    %{
      bucket: Keyword.fetch!(opts, :bucket),
      limit: Keyword.fetch!(opts, :limit),
      window_ms: Keyword.fetch!(opts, :window_ms)
    }
  end

  @impl true
  def call(conn, %{bucket: bucket, limit: limit, window_ms: window_ms}) do
    if enabled?() do
      case RateLimit.check(bucket, client_key(conn), limit, window_ms) do
        :ok ->
          conn

        {:error, :rate_limited} ->
          conn
          |> Plug.Conn.put_resp_header("retry-after", Integer.to_string(div(window_ms, 1000)))
          |> error(
            :too_many_requests,
            "rate_limited",
            "Too many requests from this device. Wait a moment and try again."
          )
          |> Plug.Conn.halt()
      end
    else
      conn
    end
  end

  defp enabled?, do: Application.get_env(:fazoura, :rate_limit_enabled, true)

  @doc "The caller's IP, as a string (`FazouraWeb.ClientIp`)."
  @spec client_key(Plug.Conn.t()) :: String.t()
  def client_key(conn), do: FazouraWeb.ClientIp.from_conn(conn)
end

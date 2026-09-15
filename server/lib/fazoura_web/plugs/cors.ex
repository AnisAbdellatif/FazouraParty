defmodule FazouraWeb.Plugs.CORS do
  @moduledoc """
  Minimal CORS for the HTTP API, so a Flutter Web build served from another origin can
  call `POST /api/rooms`. Allowed origins come from `config :fazoura, :cors_origins`
  (`:all` or a list of origin strings). WebSockets are governed by `check_origin` instead.
  """

  @behaviour Plug

  import Plug.Conn

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    origin = conn |> get_req_header("origin") |> List.first()

    if origin && allowed?(origin, Application.get_env(:fazoura, :cors_origins, [])) do
      conn
      |> put_resp_header("access-control-allow-origin", origin)
      |> put_resp_header("vary", "origin")
      |> put_resp_header("access-control-allow-methods", "GET, POST, PUT, PATCH, DELETE, OPTIONS")
      |> put_resp_header(
        "access-control-allow-headers",
        "content-type, authorization, x-owner-key"
      )
      |> put_resp_header("access-control-max-age", "600")
      |> preflight()
    else
      conn
    end
  end

  defp allowed?(_origin, :all), do: true
  defp allowed?(origin, origins) when is_list(origins), do: origin in origins

  defp preflight(%{method: "OPTIONS"} = conn), do: conn |> send_resp(204, "") |> halt()
  defp preflight(conn), do: conn
end

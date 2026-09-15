defmodule FazouraWeb.Plugs.AdminAuth do
  @moduledoc """
  HTTP Basic auth for `/admin`, from `ADMIN_USERNAME` / `ADMIN_PASSWORD`
  (`config :fazoura, :admin`).

  With no credentials configured the dashboard doesn't exist: every request gets a plain
  404, so a deployment that forgot to set them can't be logged into and doesn't advertise
  that an admin area is there at all.
  """

  import Plug.Conn

  @session_flag "admin"

  def init(opts), do: opts

  def call(conn, _opts) do
    case credentials() do
      {username, password} ->
        conn
        |> Plug.BasicAuth.basic_auth(
          username: username,
          password: password,
          realm: "Fazoura admin"
        )
        |> mark_session()

      :none ->
        conn |> send_resp(:not_found, "Not found") |> halt()
    end
  end

  @doc "Whether a LiveView session came from an authenticated admin request."
  @spec admin_session?(map()) :: boolean()
  def admin_session?(session), do: Map.get(session, @session_flag) == true

  @doc "Whether credentials are configured at all."
  @spec configured?() :: boolean()
  def configured?, do: credentials() != :none

  # Basic auth halts on failure, and a halted conn must not be given the admin flag.
  defp mark_session(%{halted: true} = conn), do: conn
  defp mark_session(conn), do: put_session(conn, @session_flag, true)

  defp credentials do
    config = Application.get_env(:fazoura, :admin, [])

    case {config[:username], config[:password]} do
      {username, password}
      when is_binary(username) and is_binary(password) and username != "" and password != "" ->
        {username, password}

      _ ->
        :none
    end
  end
end

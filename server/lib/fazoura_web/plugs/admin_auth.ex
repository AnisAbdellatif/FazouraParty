defmodule FazouraWeb.Plugs.AdminAuth do
  @moduledoc """
  HTTP Basic auth for `/admin`, from `ADMIN_USERNAME` / `ADMIN_PASSWORD`
  (`config :fazoura, :admin`).

  With no credentials configured the dashboard doesn't exist: every request gets a plain
  404, so a deployment that forgot to set them can't be logged into and doesn't advertise
  that an admin area is there at all.

  Wrong passwords are metered per address: after ten in a minute every
  request is refused with `429` until the minute is out, so the password is not open to
  guessing at the speed of the network.

  The session remembers *which* credentials it was let in with (a keyed fingerprint,
  never the password), and a LiveView checks that against the ones configured now. So
  changing `ADMIN_PASSWORD`, or unsetting it, ends every session already open rather
  than leaving it good for as long as its cookie lasts.
  """

  import Plug.Conn

  alias Fazoura.RateLimit

  @session_flag "admin"
  @failure_limit 10
  @failure_window_ms 60_000

  def init(opts), do: opts

  def call(conn, _opts) do
    case credentials() do
      {username, password} = credentials ->
        if locked_out?(conn) do
          conn |> send_resp(:too_many_requests, "Too many attempts") |> halt()
        else
          conn
          |> Plug.BasicAuth.basic_auth(
            username: username,
            password: password,
            realm: "Fazoura admin"
          )
          |> count_failure()
          |> mark_session(credentials)
        end

      :none ->
        conn |> send_resp(:not_found, "Not found") |> halt()
    end
  end

  @doc """
  Whether a LiveView session came from a request authenticated with the credentials
  configured now.
  """
  @spec admin_session?(map()) :: boolean()
  def admin_session?(session) do
    case credentials() do
      :none ->
        false

      credentials ->
        Plug.Crypto.secure_compare(to_string(session[@session_flag]), fingerprint(credentials))
    end
  end

  @doc "Whether credentials are configured at all."
  @spec configured?() :: boolean()
  def configured?, do: credentials() != :none

  # Basic auth halts on failure, and a halted conn must not be given the admin flag.
  defp mark_session(%{halted: true} = conn, _credentials), do: conn

  defp mark_session(conn, credentials),
    do: put_session(conn, @session_flag, fingerprint(credentials))

  # A browser's first request carries no credentials and is answered 401 to make it
  # ask for them; only a request that tried some and was refused is a failure.
  defp count_failure(%{halted: true} = conn) do
    if get_req_header(conn, "authorization") != [] and metered?() do
      RateLimit.check(:admin_failures, client(conn), @failure_limit, @failure_window_ms)
    end

    conn
  end

  defp count_failure(conn), do: conn

  defp locked_out?(conn) do
    metered?() and
      RateLimit.exceeded?(:admin_failures, client(conn), @failure_limit, @failure_window_ms)
  end

  defp client(conn), do: FazouraWeb.ClientIp.from_conn(conn)
  defp metered?, do: Application.get_env(:fazoura, :rate_limit_enabled, true)

  # Keyed with the endpoint's secret, so the session (encrypted as it is) never holds
  # anything that could be guessed against offline.
  defp fingerprint({username, password}) do
    secret = FazouraWeb.Endpoint.config(:secret_key_base)

    :hmac
    |> :crypto.mac(:sha256, secret, [username, 0, password])
    |> Base.url_encode64(padding: false)
  end

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

defmodule FazouraWeb.ApiHelpers do
  @moduledoc "Shared helpers for the JSON API controllers."

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  @doc "The device owner key from the `x-owner-key` header (QUIZ_FORMAT.md §4)."
  @spec owner_key(Plug.Conn.t()) :: String.t() | nil
  def owner_key(conn), do: conn |> get_req_header("x-owner-key") |> List.first()

  @spec error(Plug.Conn.t(), atom() | pos_integer(), String.t(), String.t(), map()) ::
          Plug.Conn.t()
  def error(conn, status, code, message, extra \\ %{}) do
    conn
    |> put_status(status)
    |> json(Map.merge(%{code: code, message: message}, extra))
  end

  @doc "Parses a non-negative integer query param, falling back to `default`."
  @spec int_param(term(), integer()) :: integer()
  def int_param(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> default
    end
  end

  def int_param(_value, default), do: default

  @reports_per_day 20
  @day_ms 86_400_000

  @doc """
  Whether a report from this address should be kept: at most 20 a day, quiz and player
  reports together. An admin reads a report's count as "how many people", and a
  publisher key — what makes one reporter count once — is whatever the caller sends.
  Past the quota a report is answered exactly like any other and dropped, since what
  happens to a report is not something a caller gets to probe.
  """
  @spec report_counts?(Plug.Conn.t()) :: boolean()
  def report_counts?(conn) do
    not Application.get_env(:fazoura, :rate_limit_enabled, true) or
      Fazoura.RateLimit.check(
        :reports_per_day,
        FazouraWeb.ClientIp.from_conn(conn),
        @reports_per_day,
        @day_ms
      ) == :ok
  end
end

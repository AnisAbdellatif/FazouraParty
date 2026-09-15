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
end

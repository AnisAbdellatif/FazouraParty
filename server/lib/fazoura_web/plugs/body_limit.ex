defmodule FazouraWeb.Plugs.BodyLimit do
  @moduledoc """
  Rejects an over-long request body before `Plug.Parsers` buffers it.

      plug FazouraWeb.Plugs.BodyLimit,
        default: 1_000_000,
        routes: %{["api", "rooms"] => 32_000_000, ["api", "quizzes", :_] => 32_000_000}

  A route is the request's `path_info`. A `:_` segment stands for one segment of any
  value, which is how a route carrying an id gets a limit: `["api", "quizzes", :_]` is
  `PUT /api/quizzes/<uuid>` and nothing longer.

  `Plug.Parsers` takes one `:length` for the whole endpoint, which has to be the largest
  any route needs — here 32 MB, for a private quiz sent inline with its photos. That
  would otherwise let *every* route buffer 32 MB, which is free amplification for a
  caller and real memory for the server. This narrows it to the routes that need it.

  This checks the declared `content-length`. A body sent without one — chunked — is
  refused with `411`: it would otherwise count as empty here and be read up to the
  endpoint's 32 MB on any route, before any rate limit, which let one caller make the
  server parse 32 MB a request. Every client of this API (browsers, the app, the CLI)
  sends a length. A caller who declares a length and sends more is stopped at the
  declared length by the adapter, and one who sends less simply fails to parse.
  """

  @behaviour Plug

  import FazouraWeb.ApiHelpers, only: [error: 4]

  @impl true
  def init(opts) do
    %{
      default: Keyword.fetch!(opts, :default),
      routes: Keyword.get(opts, :routes, %{})
    }
  end

  @impl true
  def call(conn, %{default: default, routes: routes}) do
    limit = limit_for(conn.path_info, routes, default)

    cond do
      unmeasured_body?(conn) ->
        conn
        |> error(
          :length_required,
          "length_required",
          "Send the request with a Content-Length."
        )
        |> Plug.Conn.halt()

      declared_length(conn) > limit ->
        too_large(conn)

      true ->
        conn
    end
  end

  defp too_large(conn) do
    conn
    |> error(
      :request_entity_too_large,
      "payload_too_large",
      "That request is too large for this endpoint."
    )
    |> Plug.Conn.halt()
  end

  # A body is coming but nobody said how long: `transfer-encoding` with no length.
  defp unmeasured_body?(conn) do
    Plug.Conn.get_req_header(conn, "content-length") == [] and
      Plug.Conn.get_req_header(conn, "transfer-encoding") != []
  end

  # An exact route wins over one with a wildcard in it, so a specific limit can never be
  # widened by a pattern that happens to also match.
  defp limit_for(path, routes, default) do
    case Map.fetch(routes, path) do
      {:ok, limit} ->
        limit

      :error ->
        Enum.find_value(routes, default, fn {route, limit} ->
          matches?(route, path) && limit
        end)
    end
  end

  defp matches?(route, path) when length(route) == length(path) do
    Enum.zip(route, path) |> Enum.all?(fn {segment, actual} -> segment in [:_, actual] end)
  end

  defp matches?(_route, _path), do: false

  defp declared_length(conn) do
    case Plug.Conn.get_req_header(conn, "content-length") do
      [value | _] ->
        case Integer.parse(value) do
          {bytes, _rest} -> bytes
          :error -> 0
        end

      [] ->
        0
    end
  end
end

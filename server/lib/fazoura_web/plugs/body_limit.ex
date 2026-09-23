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

  This checks the declared `content-length`, which a caller can lie about or omit. That
  is still worth doing — it rejects the honest large request before a byte of body is
  read — but the backstop for a lying one is `Plug.Parsers`' own `:length`, which is
  fixed at compile time and cannot be narrowed per request. So: this plug bounds what a
  route accepts, and the endpoint's 32 MB bounds everything else.
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

    if declared_length(conn) > limit do
      conn
      |> error(
        :request_entity_too_large,
        "payload_too_large",
        "That request is too large for this endpoint."
      )
      |> Plug.Conn.halt()
    else
      conn
    end
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

defmodule FazouraWeb.Plugs.CORSTest do
  @moduledoc """
  Cross-origin access exists for one case: a client served from somewhere other than
  this server — `flutter run` on a random port during development, or a web app hosted
  elsewhere. A real deployment serves the app from the API's own origin and needs none
  of this, so the allowlist is empty by default.
  """

  use FazouraWeb.ConnCase, async: false

  setup do
    original = Application.get_env(:fazoura, :cors_origins)
    on_exit(fn -> Application.put_env(:fazoura, :cors_origins, original) end)
    :ok
  end

  defp get_with_origin(conn, origin) do
    conn |> put_req_header("origin", origin) |> get(~p"/api/quizzes")
  end

  test "an origin on the allowlist is echoed back", %{conn: conn} do
    Application.put_env(:fazoura, :cors_origins, ["https://party.example.com"])

    conn = get_with_origin(conn, "https://party.example.com")

    assert get_resp_header(conn, "access-control-allow-origin") ==
             ["https://party.example.com"]

    # Caches must not serve one origin's response to another.
    assert "origin" in get_resp_header(conn, "vary")
  end

  test "an origin that is not on the allowlist gets no allowance", %{conn: conn} do
    Application.put_env(:fazoura, :cors_origins, ["https://party.example.com"])

    conn = get_with_origin(conn, "https://evil.example.com")

    assert get_resp_header(conn, "access-control-allow-origin") == []
  end

  test "with no allowlist, nothing is allowed", %{conn: conn} do
    Application.put_env(:fazoura, :cors_origins, [])

    conn = get_with_origin(conn, "http://localhost:52341")

    assert get_resp_header(conn, "access-control-allow-origin") == []
  end

  test ":all echoes whatever origin asked", %{conn: conn} do
    # What CORS_ORIGINS=* configures, for a local stack whose client is served by
    # `flutter run` on a port that changes every time.
    Application.put_env(:fazoura, :cors_origins, :all)

    for origin <- ["http://localhost:52341", "http://127.0.0.1:8080"] do
      conn = get_with_origin(conn, origin)
      assert get_resp_header(conn, "access-control-allow-origin") == [origin]
    end
  end

  test "a preflight is answered without reaching the route", %{conn: conn} do
    Application.put_env(:fazoura, :cors_origins, :all)

    conn =
      conn
      |> put_req_header("origin", "http://localhost:52341")
      |> options(~p"/api/rooms")

    assert conn.status == 204
    assert get_resp_header(conn, "access-control-allow-origin") == ["http://localhost:52341"]
    # The publisher key is a custom header, so it must be named explicitly or the
    # browser will refuse to send it.
    assert conn
           |> get_resp_header("access-control-allow-headers")
           |> Enum.join()
           |> String.contains?("x-owner-key")
  end

  test "a request with no origin is untouched", %{conn: conn} do
    Application.put_env(:fazoura, :cors_origins, :all)

    conn = get(conn, ~p"/api/quizzes")

    assert get_resp_header(conn, "access-control-allow-origin") == []
    assert json_response(conn, 200)
  end
end

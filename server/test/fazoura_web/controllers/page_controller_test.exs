defmodule FazouraWeb.PageControllerTest do
  use FazouraWeb.ConnCase, async: true

  test "serves the privacy policy", %{conn: conn} do
    conn = get(conn, "/privacy")

    assert html_response(conn, 200) =~ "Privacy Policy"
    assert get_resp_header(conn, "cache-control") == ["public, max-age=0, must-revalidate"]
  end

  test "sets no cookie", %{conn: conn} do
    # The policy says visitors get none; the page must not be the one that does.
    conn = get(conn, "/privacy")

    assert get_resp_header(conn, "set-cookie") == []
  end
end

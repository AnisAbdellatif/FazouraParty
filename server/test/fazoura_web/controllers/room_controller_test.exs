defmodule FazouraWeb.RoomControllerTest do
  use FazouraWeb.ConnCase, async: true

  test "POST /api/rooms creates a room for a built-in pack", %{conn: conn} do
    conn = post(conn, ~p"/api/rooms", %{pack_id: "general-knowledge"})

    assert %{"room_code" => code, "host_token" => token} = json_response(conn, 201)
    assert code =~ ~r/\A[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}\z/
    assert is_binary(token)
  end

  test "POST /api/rooms with an unknown pack is 404", %{conn: conn} do
    for pack_id <- ["nope", "../../etc/passwd", nil] do
      conn = post(conn, ~p"/api/rooms", %{pack_id: pack_id})
      assert json_response(conn, 404) == %{"code" => "pack_not_found"}
    end
  end

  test "GET /health", %{conn: conn} do
    assert json_response(get(conn, ~p"/health"), 200) == %{"status" => "ok"}
  end
end

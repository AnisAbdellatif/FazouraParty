defmodule FazouraWeb.RoomControllerTest do
  use FazouraWeb.ConnCase, async: false

  alias Fazoura.{QuizFixtures, Quizzes}

  setup do
    Quizzes.sync_builtin!()
    :ok
  end

  test "POST /api/rooms creates a room from a built-in quiz by slug or legacy pack_id", %{
    conn: conn
  } do
    for body <- [%{quiz_id: "general-knowledge"}, %{pack_id: "general-knowledge"}] do
      conn = post(conn, ~p"/api/rooms", body)
      assert %{"room_code" => code, "host_token" => token} = json_response(conn, 201)
      assert code =~ ~r/\A[ABCDEFGHJKLMNPQRSTUVWXYZ23456789]{6}\z/
      assert is_binary(token)
    end
  end

  test "private quizzes need the owner's key", %{conn: conn} do
    {:ok, quiz} = Quizzes.create(QuizFixtures.quiz_params(), QuizFixtures.owner_key())

    response = conn |> post(~p"/api/rooms", %{quiz_id: quiz.id}) |> json_response(404)
    assert response["code"] == "quiz_not_found"

    conn =
      conn
      |> put_req_header("x-owner-key", QuizFixtures.owner_key())
      |> post(~p"/api/rooms", %{quiz_id: quiz.id})

    assert %{"room_code" => _} = json_response(conn, 201)
  end

  test "unknown quizzes are 404", %{conn: conn} do
    for quiz_id <- ["nope", "../../etc/passwd", nil] do
      conn = post(conn, ~p"/api/rooms", %{quiz_id: quiz_id})
      assert %{"code" => "quiz_not_found"} = json_response(conn, 404)
    end
  end

  test "GET /health", %{conn: conn} do
    assert json_response(get(conn, ~p"/health"), 200) == %{"status" => "ok"}
  end
end

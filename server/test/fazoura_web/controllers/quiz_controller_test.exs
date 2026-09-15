defmodule FazouraWeb.QuizControllerTest do
  use FazouraWeb.ConnCase, async: false

  alias Fazoura.{QuizFixtures, Quizzes}

  @owner QuizFixtures.owner_key()
  @other QuizFixtures.other_key()

  setup %{conn: conn} do
    Quizzes.sync_builtin!()
    %{conn: put_req_header(conn, "accept", "application/json")}
  end

  defp as(conn, key), do: put_req_header(conn, "x-owner-key", key)

  defp create!(conn, attrs \\ %{}) do
    conn
    |> as(@owner)
    |> post(~p"/api/quizzes", QuizFixtures.quiz_params(attrs))
    |> json_response(201)
  end

  test "create returns the full owned document", %{conn: conn} do
    doc = create!(conn)

    assert %{
             "format_version" => 1,
             "source" => "custom",
             "visibility" => "private",
             "is_owner" => true,
             "question_count" => 1,
             "has_photos" => false,
             "default_settings" => %{"time_limit_ms" => 30_000, "difficulty_multiplier" => false},
             "questions" => [
               %{"type" => "text", "accepted_answers" => ["Steven Spielberg", "Spielberg"]}
             ]
           } = doc
  end

  test "create requires an owner key and a valid document", %{conn: conn} do
    assert %{"code" => "owner_key_required"} =
             conn |> post(~p"/api/quizzes", QuizFixtures.quiz_params()) |> json_response(401)

    assert %{"code" => "invalid_quiz", "errors" => errors} =
             conn
             |> as(@owner)
             |> post(
               ~p"/api/quizzes",
               QuizFixtures.quiz_params(%{"title" => "", "questions" => []})
             )
             |> json_response(422)

    assert %{"title" => _, "questions" => _} = errors
  end

  test "index lists public quizzes without questions, and mine with a key", %{conn: conn} do
    private = create!(conn)
    public = create!(conn, %{"title" => "Open Quiz", "visibility" => "public"})

    %{"quizzes" => listed, "next_offset" => nil} =
      conn |> as(@other) |> get(~p"/api/quizzes") |> json_response(200)

    assert Enum.map(listed, & &1["title"]) == ["General Knowledge", "Open Quiz"]
    refute Enum.any?(listed, &Map.has_key?(&1, "questions"))
    assert Enum.all?(listed, &(&1["is_owner"] == false))

    %{"quizzes" => mine} =
      conn |> as(@owner) |> get(~p"/api/quizzes?scope=mine") |> json_response(200)

    assert mine |> Enum.map(& &1["id"]) |> Enum.sort() == Enum.sort([private["id"], public["id"]])
    assert Enum.all?(mine, & &1["is_owner"])

    assert %{"code" => "owner_key_required"} =
             conn |> get(~p"/api/quizzes?scope=mine") |> json_response(401)

    %{"quizzes" => [%{"title" => "Open Quiz"}]} =
      conn |> get(~p"/api/quizzes?q=open&limit=5") |> json_response(200)

    %{"quizzes" => [_], "next_offset" => 1} =
      conn |> get(~p"/api/quizzes?limit=1") |> json_response(200)
  end

  test "show hides answers from non-owners and private quizzes from others", %{conn: conn} do
    private = create!(conn)

    assert %{"code" => "quiz_not_found"} =
             conn |> as(@other) |> get(~p"/api/quizzes/#{private["id"]}") |> json_response(404)

    assert %{"questions" => [_]} =
             conn |> as(@owner) |> get(~p"/api/quizzes/#{private["id"]}") |> json_response(200)

    builtin = conn |> get(~p"/api/quizzes/general-knowledge") |> json_response(200)
    assert %{"source" => "builtin", "question_count" => 20} = builtin
    refute Map.has_key?(builtin, "questions")
  end

  test "owner updates, changes visibility and deletes", %{conn: conn} do
    %{"id" => id} = create!(conn)

    replacement =
      QuizFixtures.quiz_params(%{
        "title" => "Renamed",
        "questions" => [
          %{
            "type" => "text",
            "prompt" => "One",
            "accepted_answers" => ["1"],
            "difficulty" => "hard"
          },
          %{"type" => "text", "prompt" => "Two", "accepted_answers" => ["2"]}
        ]
      })

    assert %{"code" => "quiz_not_found"} =
             conn |> as(@other) |> put(~p"/api/quizzes/#{id}", replacement) |> json_response(404)

    assert %{
             "title" => "Renamed",
             "question_count" => 2,
             "questions" => [%{"difficulty" => "hard"}, _]
           } =
             conn |> as(@owner) |> put(~p"/api/quizzes/#{id}", replacement) |> json_response(200)

    assert %{"visibility" => "public"} =
             conn
             |> as(@owner)
             |> patch(~p"/api/quizzes/#{id}", %{visibility: "public"})
             |> json_response(200)

    assert %{"id" => ^id} = conn |> get(~p"/api/quizzes/#{id}") |> json_response(200)

    assert %{"code" => "invalid_quiz"} =
             conn
             |> as(@owner)
             |> patch(~p"/api/quizzes/#{id}", %{visibility: "friends"})
             |> json_response(422)

    assert conn |> as(@other) |> delete(~p"/api/quizzes/#{id}") |> json_response(404)
    assert conn |> as(@owner) |> delete(~p"/api/quizzes/#{id}") |> response(204)
    assert conn |> get(~p"/api/quizzes/#{id}") |> json_response(404)
  end

  test "CORS preflight allows the owner key header and write methods", %{conn: conn} do
    Application.put_env(:fazoura, :cors_origins, :all)
    on_exit(fn -> Application.put_env(:fazoura, :cors_origins, []) end)

    conn =
      conn
      |> put_req_header("origin", "http://localhost:5555")
      |> options(~p"/api/quizzes")

    assert response(conn, 204)
    assert get_resp_header(conn, "access-control-allow-headers") |> hd() =~ "x-owner-key"
    assert get_resp_header(conn, "access-control-allow-methods") |> hd() =~ "PATCH"
  end
end

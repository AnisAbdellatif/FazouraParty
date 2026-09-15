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

  test "publishing returns the full document, always public", %{conn: conn} do
    doc = create!(conn, %{"visibility" => "private"})

    assert %{
             "format_version" => 1,
             "source" => "custom",
             "visibility" => "public",
             "is_owner" => true,
             "question_count" => 1,
             "has_photos" => false,
             "default_settings" => %{"time_limit_ms" => 30_000, "difficulty_multiplier" => false},
             "questions" => [
               %{"type" => "text", "accepted_answers" => ["Steven Spielberg", "Spielberg"]}
             ]
           } = doc
  end

  test "publishing requires a publisher key and a valid document", %{conn: conn} do
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

  test "index lists published quizzes without questions", %{conn: conn} do
    create!(conn, %{"title" => "Open Quiz"})

    %{"quizzes" => listed, "next_offset" => nil} =
      conn |> as(@other) |> get(~p"/api/quizzes") |> json_response(200)

    assert Enum.map(listed, & &1["title"]) == ["General Knowledge", "Open Quiz"]
    refute Enum.any?(listed, &Map.has_key?(&1, "questions"))
    assert Enum.all?(listed, &(&1["is_owner"] == false))

    %{"quizzes" => mine} = conn |> as(@owner) |> get(~p"/api/quizzes") |> json_response(200)
    assert Enum.map(mine, & &1["is_owner"]) == [false, true]

    %{"quizzes" => [%{"title" => "Open Quiz"}]} =
      conn |> get(~p"/api/quizzes?q=open&limit=5") |> json_response(200)

    %{"quizzes" => [_], "next_offset" => 1} =
      conn |> get(~p"/api/quizzes?limit=1") |> json_response(200)
  end

  test "index filters by tag and /api/tags lists the tags in use", %{conn: conn} do
    create!(conn, %{"title" => "Open Quiz", "tags" => ["Movies", "quiz night"]})

    %{"quizzes" => movies} = conn |> get(~p"/api/quizzes?tag=movies") |> json_response(200)
    assert Enum.map(movies, & &1["title"]) == ["Open Quiz"]
    assert hd(movies)["tags"] == ["movies", "quiz night"]

    %{"quizzes" => searched} = conn |> get(~p"/api/quizzes?q=quiz night") |> json_response(200)
    assert Enum.map(searched, & &1["title"]) == ["Open Quiz"]

    %{"tags" => tags, "suggested" => suggested} =
      conn |> get(~p"/api/tags") |> json_response(200)

    assert %{"tag" => "movies", "count" => 1} in tags
    assert %{"tag" => "general", "count" => 1} in tags
    assert "pop culture" in suggested

    assert conn
           |> get(~p"/api/tags?limit=1")
           |> json_response(200)
           |> Map.fetch!("tags")
           |> length() == 1
  end

  test "show hides answers from everyone but the publisher", %{conn: conn} do
    %{"id" => id} = create!(conn)

    other = conn |> as(@other) |> get(~p"/api/quizzes/#{id}") |> json_response(200)
    refute Map.has_key?(other, "questions")

    assert %{"questions" => [_]} =
             conn |> as(@owner) |> get(~p"/api/quizzes/#{id}") |> json_response(200)

    builtin = conn |> get(~p"/api/quizzes/general-knowledge") |> json_response(200)
    assert %{"source" => "builtin", "question_count" => 20} = builtin
    refute Map.has_key?(builtin, "questions")

    assert %{"code" => "quiz_not_found"} =
             conn |> get(~p"/api/quizzes/nope") |> json_response(404)
  end

  test "publisher updates and unpublishes", %{conn: conn} do
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

    assert conn |> as(@other) |> delete(~p"/api/quizzes/#{id}") |> json_response(404)
    assert conn |> as(@owner) |> delete(~p"/api/quizzes/#{id}") |> response(204)
    assert conn |> get(~p"/api/quizzes/#{id}") |> json_response(404)
  end

  test "CORS preflight allows the publisher key header and write methods", %{conn: conn} do
    Application.put_env(:fazoura, :cors_origins, :all)
    on_exit(fn -> Application.put_env(:fazoura, :cors_origins, []) end)

    conn =
      conn
      |> put_req_header("origin", "http://localhost:5555")
      |> options(~p"/api/quizzes")

    assert response(conn, 204)
    assert get_resp_header(conn, "access-control-allow-headers") |> hd() =~ "x-owner-key"
    assert get_resp_header(conn, "access-control-allow-methods") |> hd() =~ "DELETE"
  end
end

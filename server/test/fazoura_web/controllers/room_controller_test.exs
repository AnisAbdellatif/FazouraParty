defmodule FazouraWeb.RoomControllerTest do
  use FazouraWeb.ConnCase, async: false

  alias Fazoura.{QuizFixtures, Quizzes}
  alias Fazoura.Rooms.Images

  # A real 1x1 PNG: uploads are validated structurally, not just by magic bytes.
  @png QuizFixtures.png()

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

  test "published quizzes are hostable by anyone", %{conn: conn} do
    {:ok, quiz} = Quizzes.create(QuizFixtures.quiz_params(), QuizFixtures.owner_key())

    assert %{"room_code" => _} =
             conn |> post(~p"/api/rooms", %{quiz_id: quiz.id}) |> json_response(201)
  end

  test "unknown quizzes are 404", %{conn: conn} do
    for quiz_id <- ["nope", "../../etc/passwd", nil] do
      conn = post(conn, ~p"/api/rooms", %{quiz_id: quiz_id})
      assert %{"code" => "quiz_not_found"} = json_response(conn, 404)
    end
  end

  describe "private quizzes sent inline" do
    defp inline_quiz(attrs \\ %{}) do
      QuizFixtures.quiz_params(
        Map.merge(
          %{
            "questions" => [
              %{
                "type" => "text_photo",
                "prompt" => "Which film?",
                "accepted_answers" => ["Alien"],
                "image" => %{"data" => Base.encode64(@png), "alt" => "A still"}
              },
              %{"type" => "text", "prompt" => "Second?", "accepted_answers" => ["Yes"]}
            ]
          },
          attrs
        )
      )
    end

    test "creates a room without storing the quiz; photos live as long as the room", %{
      conn: conn
    } do
      quiz_count = Fazoura.Repo.aggregate(Fazoura.Quizzes.Quiz, :count)

      %{"room_code" => code} =
        conn |> post(~p"/api/rooms", %{quiz: inline_quiz()}) |> json_response(201)

      assert Fazoura.Repo.aggregate(Fazoura.Quizzes.Quiz, :count) == quiz_count

      [{pid, _}] = Registry.lookup(Fazoura.Rooms.Registry, code)
      %{game: game} = :sys.get_state(pid)
      [%{image_url: url, prompt: "Which film?"}, %{image_url: nil}] = game.pack.questions
      "/api/room-images/" <> key = URI.parse(url).path

      image = build_conn() |> put_req_header("accept", "image/*") |> get(url)
      assert response(image, 200) == @png
      assert get_resp_header(image, "content-type") == ["image/png"]

      ref = Process.monitor(pid)
      DynamicSupervisor.terminate_child(Fazoura.Rooms.Supervisor, pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}
      _ = :sys.get_state(Images)

      assert Images.fetch(key) == :error

      assert %{"code" => "image_not_found"} =
               build_conn() |> get(~p"/api/room-images/#{key}") |> json_response(404)
    end

    test "rejects invalid quizzes and photos", %{conn: conn} do
      assert %{"code" => "invalid_quiz", "errors" => %{"questions" => _}} =
               conn
               |> post(~p"/api/rooms", %{quiz: inline_quiz(%{"questions" => []})})
               |> json_response(422)

      bad_photo =
        inline_quiz(%{
          "questions" => [
            %{
              "type" => "text_photo",
              "prompt" => "Which film?",
              "accepted_answers" => ["Alien"],
              "image" => %{"data" => Base.encode64("GIF89a")}
            }
          ]
        })

      assert %{"code" => "unsupported_image"} =
               conn |> post(~p"/api/rooms", %{quiz: bad_photo}) |> json_response(415)
    end
  end

  test "GET /health", %{conn: conn} do
    assert json_response(get(conn, ~p"/health"), 200) == %{"status" => "ok"}
  end
end

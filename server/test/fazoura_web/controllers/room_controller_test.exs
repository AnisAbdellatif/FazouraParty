defmodule FazouraWeb.RoomControllerTest do
  use FazouraWeb.ConnCase, async: false

  alias Fazoura.{QuizFixtures, Quizzes}
  alias Fazoura.Rooms.Images

  # A real 1x1 PNG: uploads are validated structurally, not just by magic bytes.
  @png QuizFixtures.png()

  setup do
    QuizFixtures.builtin!("general-knowledge")
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

  describe "public rooms" do
    test "a listed room is on GET /api/rooms, and one joined by code is not", %{conn: conn} do
      listed = conn |> post(~p"/api/rooms", %{listed: true}) |> json_response(201)
      code_only = conn |> post(~p"/api/rooms", %{}) |> json_response(201)
      also_code_only = conn |> post(~p"/api/rooms", %{listed: false}) |> json_response(201)

      rooms = conn |> get(~p"/api/rooms") |> json_response(200) |> Map.fetch!("rooms")
      codes = Enum.map(rooms, & &1["room_code"])

      assert listed["room_code"] in codes
      refute code_only["room_code"] in codes
      refute also_code_only["room_code"] in codes

      entry = Enum.find(rooms, &(&1["room_code"] == listed["room_code"]))

      # Nothing anybody typed: the list is read by strangers.
      assert entry == %{
               "room_code" => listed["room_code"],
               "phase" => "lobby",
               "pack_titles" => [],
               "player_count" => 0,
               "room_size" => Fazoura.Game.max_players(),
               "question_index" => nil,
               "question_count" => 0
             }
    end

    test "a stored quiz can open a listed room; one sent inline cannot", %{conn: conn} do
      assert %{"room_code" => _} =
               conn
               |> post(~p"/api/rooms", %{quiz_id: "general-knowledge", listed: true})
               |> json_response(201)

      assert %{"code" => "quiz_not_public"} =
               conn
               |> post(~p"/api/rooms", %{quiz: QuizFixtures.quiz_params(), listed: true})
               |> json_response(422)
    end

    test "a room full at the size its host chose is off the list", %{conn: conn} do
      %{"room_code" => code, "host_token" => host_token} =
        conn |> post(~p"/api/rooms", %{listed: true}) |> json_response(201)

      {:ok, _reply, _room} = Fazoura.Rooms.join(code, self(), %{"host_token" => host_token})
      :ok = Fazoura.Rooms.intent(code, self(), {:set_room_size, %{"room_size" => 1}})

      listed_codes = fn ->
        conn
        |> get(~p"/api/rooms")
        |> json_response(200)
        |> Map.fetch!("rooms")
        |> Enum.map(& &1["room_code"])
      end

      assert code in listed_codes.()

      player = spawn_link(fn -> Process.sleep(:infinity) end)
      {:ok, _reply, _room} = Fazoura.Rooms.join(code, player, %{"display_name" => "Sam"})
      refute code in listed_codes.()
    end

    test "listed must be a boolean", %{conn: conn} do
      assert %{"code" => "invalid_payload"} =
               conn |> post(~p"/api/rooms", %{listed: "yes"}) |> json_response(422)
    end
  end

  test "GET /health", %{conn: conn} do
    assert json_response(get(conn, ~p"/health"), 200) == %{"status" => "ok"}
  end

  describe "GET /api/rooms/:code" do
    setup %{conn: conn} do
      %{"room_code" => code, "host_token" => token} =
        conn |> post(~p"/api/rooms", %{quiz_id: "general-knowledge"}) |> json_response(201)

      %{code: code, token: token}
    end

    test "tells the host the room they remember is still there", %{
      conn: conn,
      code: code,
      token: token
    } do
      body =
        conn
        |> put_req_header("x-host-token", token)
        |> get(~p"/api/rooms/#{code}")
        |> json_response(200)

      assert body == %{"room_code" => code, "phase" => "lobby", "players" => 0}
    end

    test "404 once the room has ended", %{conn: conn, code: code, token: token} do
      assert Fazoura.Rooms.shutdown_all() >= 1

      assert %{"code" => "room_not_found"} =
               conn
               |> put_req_header("x-host-token", token)
               |> get(~p"/api/rooms/#{code}")
               |> json_response(404)
    end

    test "404 for a room that never existed", %{conn: conn, token: token} do
      assert %{"code" => "room_not_found"} =
               conn
               |> put_req_header("x-host-token", token)
               |> get(~p"/api/rooms/ZZZZZZ")
               |> json_response(404)
    end

    # The point of the header: without the current token this says nothing at
    # all, so live room codes cannot be found by guessing.
    test "404 without a token, and with somebody else\'s", %{
      conn: conn,
      code: code
    } do
      assert %{"code" => "room_not_found"} =
               conn |> get(~p"/api/rooms/#{code}") |> json_response(404)

      %{"host_token" => other} =
        conn |> post(~p"/api/rooms", %{quiz_id: "general-knowledge"}) |> json_response(201)

      assert %{"code" => "room_not_found"} =
               conn
               |> put_req_header("x-host-token", other)
               |> get(~p"/api/rooms/#{code}")
               |> json_response(404)
    end

    test "404 once the role has moved on, so a demoted host forgets the room", %{
      conn: conn,
      code: code,
      token: token
    } do
      # A host who drops with somebody else connected is replaced, and the
      # generation bump retires their token (PROTOCOL.md §3.4).
      {:ok, _reply, _pid} = Fazoura.Rooms.join(code, self(), %{"display_name" => "Sam"})

      host = spawn(fn -> Process.sleep(:infinity) end)
      {:ok, _reply, _pid} = Fazoura.Rooms.join(code, host, %{"host_token" => token})
      Process.exit(host, :kill)
      # Let the room notice the monitor fire before asking.
      Process.sleep(50)

      assert %{"code" => "room_not_found"} =
               conn
               |> put_req_header("x-host-token", token)
               |> get(~p"/api/rooms/#{code}")
               |> json_response(404)
    end
  end
end

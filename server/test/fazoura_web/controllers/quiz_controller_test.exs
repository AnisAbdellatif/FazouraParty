defmodule FazouraWeb.QuizControllerTest do
  use FazouraWeb.ConnCase, async: false

  alias Fazoura.QuizFixtures
  alias Fazoura.Quizzes.Reports
  alias Fazoura.Quizzes.Review

  @owner QuizFixtures.owner_key()
  @other QuizFixtures.other_key()

  setup %{conn: conn} do
    QuizFixtures.builtin!("general-knowledge")
    %{conn: put_req_header(conn, "accept", "application/json")}
  end

  defp as(conn, key), do: put_req_header(conn, "x-owner-key", key)

  # What the API takes: a `.fazoura` package, which goes into the queue (§4).
  defp submit!(conn, attrs \\ %{}, photos \\ %{}) do
    conn
    |> as(@owner)
    |> post(~p"/api/quizzes", %{"file" => QuizFixtures.package_upload(attrs, photos)})
    |> json_response(201)
  end

  # A quiz that is actually live: submitted, then approved. Anything expecting
  # a quiz other people can find has to come through the queue first.
  defp create!(conn, attrs \\ %{}, photos \\ %{}) do
    submission = submit!(conn, attrs, photos)
    {:ok, quiz} = Review.approve(submission["id"])
    conn |> get(~p"/api/quizzes/#{quiz.id}") |> json_response(200)
  end

  test "a file that is not a package is refused, not a crash", %{conn: conn} do
    path = Plug.Upload.random_file!("fazoura-test")
    File.write!(path, "not a zip")
    upload = %Plug.Upload{path: path, filename: "q.fazoura", content_type: "application/zip"}

    assert %{"code" => "invalid_archive"} =
             conn
             |> as(@owner)
             |> post(~p"/api/quizzes", %{"file" => upload})
             |> json_response(422)
  end

  test "publishing queues the package rather than publishing it", %{conn: conn} do
    assert %{
             "id" => id,
             "status" => "pending",
             "title" => "Movie Night",
             "question_count" => 1,
             "has_photos" => false,
             "quiz_id" => nil
           } = submit!(conn)

    # Nothing is public, and nothing is a quiz.
    assert %{"quizzes" => listed} = conn |> get(~p"/api/quizzes") |> json_response(200)
    refute "Movie Night" in Enum.map(listed, & &1["title"])

    assert %{"code" => "quiz_not_found"} =
             conn |> post(~p"/api/rooms", %{quiz_id: id}) |> json_response(404)
  end

  test "an app too old to build a package is told to update", %{conn: conn} do
    assert %{"code" => "package_required"} =
             conn
             |> as(@owner)
             |> post(~p"/api/quizzes", QuizFixtures.quiz_params())
             |> json_response(422)
  end

  test "a device sees what it submitted, and nobody else's", %{conn: conn} do
    %{"id" => id} = submit!(conn)

    assert %{"submissions" => [%{"id" => ^id, "status" => "pending"}]} =
             conn |> as(@owner) |> get(~p"/api/submissions") |> json_response(200)

    assert %{"submissions" => []} =
             conn |> as(@other) |> get(~p"/api/submissions") |> json_response(200)
  end

  test "a rejection comes back with its reason", %{conn: conn} do
    %{"id" => id} = submit!(conn)
    {:ok, _} = Review.reject(id, "Question 1 is not suitable.")

    assert %{"submissions" => [%{"status" => "rejected", "review_note" => note}]} =
             conn |> as(@owner) |> get(~p"/api/submissions") |> json_response(200)

    assert note == "Question 1 is not suitable."
  end

  test "a submission can be withdrawn by the device that sent it, and nobody else", %{conn: conn} do
    %{"id" => id} = submit!(conn)

    assert conn |> as(@other) |> delete(~p"/api/submissions/#{id}") |> response(404)
    assert conn |> as(@owner) |> delete(~p"/api/submissions/#{id}") |> response(204)

    assert %{"submissions" => []} =
             conn |> as(@owner) |> get(~p"/api/submissions") |> json_response(200)
  end

  test "approving publishes it, owned by the device that sent it", %{conn: conn} do
    doc = create!(conn)

    assert %{
             "format_version" => "1.0",
             "source" => "custom",
             "visibility" => "public",
             "question_count" => 1,
             "has_photos" => false,
             "default_settings" => %{"time_limit_ms" => 30_000, "difficulty_multiplier" => false}
           } = doc

    assert %{"is_owner" => true, "questions" => [%{"accepted_answers" => _}]} =
             conn |> as(@owner) |> get(~p"/api/quizzes/#{doc["id"]}") |> json_response(200)
  end

  test "editing a public quiz sends it back to the queue", %{conn: conn} do
    %{"id" => id} = create!(conn)

    assert %{"status" => "pending", "replaces_quiz_id" => ^id} =
             conn
             |> as(@owner)
             |> put(~p"/api/quizzes/#{id}", %{
               "file" => QuizFixtures.package_upload(%{"title" => "Swapped"})
             })
             |> json_response(200)

    # Until somebody approves it, the live quiz is the one that was reviewed.
    assert %{"title" => "Movie Night"} =
             conn |> get(~p"/api/quizzes/#{id}") |> json_response(200)
  end

  test "submitting requires a publisher key and a package with a quiz in it", %{conn: conn} do
    assert %{"code" => "owner_key_required"} =
             conn
             |> post(~p"/api/quizzes", %{"file" => QuizFixtures.package_upload()})
             |> json_response(401)

    assert %{"code" => "invalid_quiz"} =
             conn
             |> as(@owner)
             |> post(~p"/api/quizzes", %{
               "file" => QuizFixtures.package_upload(%{"title" => "", "questions" => []})
             })
             |> json_response(422)
  end

  test "index lists published quizzes without questions", %{conn: conn} do
    create!(conn, %{"title" => "Open Quiz"})

    %{"quizzes" => listed, "next_offset" => nil} =
      conn |> as(@other) |> get(~p"/api/quizzes") |> json_response(200)

    assert Enum.map(listed, & &1["title"]) |> MapSet.new() ==
             MapSet.new(["General Knowledge", "Open Quiz"])

    refute Enum.any?(listed, &Map.has_key?(&1, "questions"))
    assert Enum.all?(listed, &(&1["is_owner"] == false))

    %{"quizzes" => mine} = conn |> as(@owner) |> get(~p"/api/quizzes") |> json_response(200)
    assert Enum.count(mine, & &1["is_owner"]) == 1

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
    assert %{"source" => "builtin", "question_count" => 1} = builtin
    refute Map.has_key?(builtin, "questions")

    assert %{"code" => "quiz_not_found"} =
             conn |> get(~p"/api/quizzes/nope") |> json_response(404)
  end

  test "explicit offline download returns answers to any client", %{conn: conn} do
    %{"id" => id} = create!(conn)

    assert %{
             "is_owner" => false,
             "questions" => [%{"accepted_answers" => ["Steven Spielberg", "Spielberg"]}]
           } =
             conn
             |> as(@other)
             |> get(~p"/api/quizzes/#{id}/download")
             |> json_response(200)

    assert %{"is_owner" => true} =
             conn |> as(@owner) |> get(~p"/api/quizzes/#{id}/download") |> json_response(200)

    assert %{"questions" => questions} =
             conn
             |> get(~p"/api/quizzes/general-knowledge/download")
             |> json_response(200)

    assert length(questions) == 1
  end

  describe "a quiz a public room is playing" do
    # Everyone in a public room sees its quiz's title, and a title finds the quiz:
    # while the room has it, the answers are not to be had for the asking.
    setup %{conn: conn} do
      %{"id" => id} = create!(conn)
      {:ok, quiz} = Fazoura.Quizzes.fetch(id)
      %{id: id, pack: Fazoura.Quizzes.to_pack(quiz)}
    end

    test "cannot be downloaded or archived while it is", %{conn: conn, id: id, pack: pack} do
      {:ok, code, _token} = Fazoura.Rooms.create(pack, listed: true)

      assert %{"code" => "quiz_in_play"} =
               conn |> get(~p"/api/quizzes/#{id}/download") |> json_response(409)

      assert %{"code" => "quiz_in_play"} =
               conn |> get(~p"/api/quizzes/#{id}/archive") |> json_response(409)

      # And the public list says nothing about which quiz it is.
      # Other tests' rooms may be listed too; this one is the one that matters.
      assert %{"rooms" => rooms} = conn |> get(~p"/api/rooms") |> json_response(200)
      assert room = Enum.find(rooms, &(&1["room_code"] == code))
      refute Map.has_key?(room, "quiz_ids")
      refute inspect(room) =~ id
    end

    test "a room only people with the code can join does not hold it back", %{
      conn: conn,
      id: id,
      pack: pack
    } do
      {:ok, _code, _token} = Fazoura.Rooms.create(pack, listed: false)
      assert conn |> get(~p"/api/quizzes/#{id}/download") |> json_response(200)
    end
  end

  test "offline archive is a ZIP download", %{conn: conn} do
    %{"id" => id} = create!(conn)

    response = conn |> as(@other) |> get(~p"/api/quizzes/#{id}/archive")

    assert response.status == 200
    assert ["application/zip" <> _] = get_resp_header(response, "content-type")
    assert <<0x50, 0x4B, _rest::binary>> = response.resp_body
  end

  test "asking for a ZIP gets one, as the app asks", %{conn: conn} do
    %{"id" => id} = create!(conn)

    response =
      conn
      |> as(@other)
      |> put_req_header("accept", "application/zip")
      |> get(~p"/api/quizzes/#{id}/archive")

    assert response.status == 200
    assert <<0x50, 0x4B, _rest::binary>> = response.resp_body
  end

  test "an archive carries the manifest and every photo", %{conn: conn} do
    %{"id" => id} = create_with_photo!(conn, %{"alt" => "a photo"})
    key = photo_key!(id)

    response = conn |> as(@other) |> get(~p"/api/quizzes/#{id}/archive")
    assert response.status == 200

    {:ok, entries} = :zip.unzip(response.resp_body, [:memory])
    names = Enum.map(entries, fn {name, _binary} -> to_string(name) end)

    assert "manifest.json" in names
    assert "media/" <> ^key = Enum.find(names, &String.starts_with?(&1, "media/"))

    {_name, manifest} = Enum.find(entries, fn {name, _} -> name == ~c"manifest.json" end)
    document = Jason.decode!(manifest)

    # The point of the archive: answers and photos travel with the questions,
    # by a path into the archive rather than a URL (QUIZ_FORMAT.md §5.3b).
    assert [question] = document["quiz"]["questions"]
    assert question["accepted_answers"] == ["a"]
    assert question["image"] == %{"path" => "media/" <> key, "alt" => "a photo"}
  end

  test "a quiz whose photo is gone is refused, not a crash", %{conn: conn} do
    %{"id" => id} = create_with_photo!(conn)
    key = photo_key!(id)

    # The uploads volume lost the file — a restore that missed it, or a sweep
    # that ran early. The quiz still references it.
    File.rm!(Path.join(Fazoura.Uploads.dir(), key))

    assert %{"code" => "image_not_found"} =
             conn |> as(@other) |> get(~p"/api/quizzes/#{id}/archive") |> json_response(404)
  end

  # A live quiz with one photo question, the photo carried in its package as a
  # device sends it.
  defp create_with_photo!(conn, image \\ %{}) do
    create!(
      conn,
      %{
        "questions" => [
          %{
            "type" => "text_photo",
            "prompt" => "What is this?",
            "accepted_answers" => ["a"],
            "image" => Map.put(image, "path", "media/still.png")
          }
        ]
      },
      %{"media/still.png" => QuizFixtures.png()}
    )
  end

  # Where approval stored that photo.
  defp photo_key!(quiz_id) do
    import Ecto.Query

    Fazoura.Repo.one!(
      from q in Fazoura.Quizzes.Question, where: q.quiz_id == ^quiz_id, select: q.image_key
    )
  end

  test "publisher updates and unpublishes", %{conn: conn} do
    %{"id" => id} = create!(conn)

    replacement = fn ->
      %{
        "file" =>
          QuizFixtures.package_upload(%{
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
      }
    end

    assert %{"code" => "not_found"} =
             conn
             |> as(@other)
             |> put(~p"/api/quizzes/#{id}", replacement.())
             |> json_response(404)

    # An edit is a submission: it goes to the queue, and the live quiz is
    # unchanged until somebody approves it.
    assert %{"status" => "pending", "id" => edit_id} =
             conn
             |> as(@owner)
             |> put(~p"/api/quizzes/#{id}", replacement.())
             |> json_response(200)

    {:ok, _} = Review.approve(edit_id)

    # Approving replaces the quiz in place, keeping its id, so anybody who
    # saved it is looking at the same quiz rather than a second copy.
    assert %{
             "id" => ^id,
             "title" => "Renamed",
             "question_count" => 2,
             "questions" => [%{"difficulty" => "hard"}, _]
           } = conn |> as(@owner) |> get(~p"/api/quizzes/#{id}") |> json_response(200)

    assert conn |> as(@other) |> delete(~p"/api/quizzes/#{id}") |> json_response(404)
    assert conn |> as(@owner) |> delete(~p"/api/quizzes/#{id}") |> response(204)
    assert conn |> get(~p"/api/quizzes/#{id}") |> json_response(404)
  end

  describe "reporting a public quiz" do
    test "anybody can report one, and is told nothing back", %{conn: conn} do
      quiz = QuizFixtures.published!()

      assert conn
             |> as(@other)
             |> post(~p"/api/quizzes/#{quiz.id}/report", %{
               "reason" => "sexual",
               "note" => "Question 2."
             })
             |> response(204)

      assert [queued] = Reports.open()
      assert queued.quiz.id == quiz.id
      assert [report] = queued.reports
      assert report.reason == "sexual"
      assert report.note == "Question 2."
    end

    test "the publisher may report their own, pointless as that is", %{conn: conn} do
      quiz = QuizFixtures.published!()

      assert conn
             |> as(@owner)
             |> post(~p"/api/quizzes/#{quiz.id}/report", %{"reason" => "spam"})
             |> response(204)
    end

    test "a made-up reason is refused", %{conn: conn} do
      quiz = QuizFixtures.published!()

      assert %{"code" => "invalid_report", "message" => message} =
               conn
               |> as(@other)
               |> post(~p"/api/quizzes/#{quiz.id}/report", %{"reason" => "boring"})
               |> json_response(422)

      assert message =~ "sexual"
      assert Reports.open() == []
    end

    test "a quiz nobody published cannot be reported", %{conn: conn} do
      assert conn
             |> as(@other)
             |> post(~p"/api/quizzes/#{Ecto.UUID.generate()}/report", %{"reason" => "spam"})
             |> json_response(404)
    end

    test "without a key there is nothing to count devices by", %{conn: conn} do
      quiz = QuizFixtures.published!()

      assert %{"code" => "owner_key_required"} =
               conn
               |> post(~p"/api/quizzes/#{quiz.id}/report", %{"reason" => "spam"})
               |> json_response(401)
    end

    test "the answer never says what an admin has already decided", %{conn: conn} do
      quiz = QuizFixtures.published!()
      {:ok, _} = Reports.submit(quiz.id, @other, %{"reason" => "spam"})
      {:ok, 1} = Reports.dismiss(quiz.id)

      # Same empty answer as the first report: a caller cannot probe moderation
      # state by watching how the endpoint replies.
      assert conn
             |> as(@other)
             |> post(~p"/api/quizzes/#{quiz.id}/report", %{"reason" => "hate"})
             |> response(204) == ""
    end
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

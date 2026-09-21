defmodule FazouraWeb.AdminLiveTest do
  use FazouraWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  import Ecto.Query

  alias Fazoura.{QuizFixtures, Quizzes, Repo, Rooms, Settings, Uploads}
  alias Fazoura.Quizzes.{Archive, Quiz, Tag}

  @username "admin"
  @password "test-admin-password"

  setup %{conn: conn} do
    QuizFixtures.builtin!("general-knowledge")
    {:ok, quiz} = Quizzes.create(QuizFixtures.quiz_params(), QuizFixtures.owner_key())
    %{conn: as_admin(conn), quiz: quiz}
  end

  defp as_admin(conn, password \\ @password) do
    put_req_header(conn, "authorization", Plug.BasicAuth.encode_basic_auth(@username, password))
  end

  defp stop_room(code) do
    case Registry.lookup(Fazoura.Rooms.Registry, code) do
      [{pid, _value}] -> DynamicSupervisor.terminate_child(Fazoura.Rooms.Supervisor, pid)
      [] -> :ok
    end
  end

  describe "access" do
    test "the dashboard needs the configured credentials", %{conn: conn} do
      assert build_conn() |> get(~p"/admin") |> response(401)
      assert build_conn() |> as_admin("wrong") |> get(~p"/admin") |> response(401)
      assert {:ok, _view, html} = live(conn, ~p"/admin")
      assert html =~ "FAZOURA"
    end

    test "with no credentials configured there is no dashboard at all" do
      Application.put_env(:fazoura, :admin, username: nil, password: nil)

      on_exit(fn ->
        Application.put_env(:fazoura, :admin, username: @username, password: @password)
      end)

      assert build_conn() |> get(~p"/admin") |> response(404)
      assert build_conn() |> as_admin() |> get(~p"/admin/quizzes") |> response(404)
    end
  end

  describe "stats" do
    test "shows the library and the rooms running now", %{conn: conn} do
      {:ok, code, _token} = Rooms.create(QuizFixtures.pack())
      on_exit(fn -> stop_room(code) end)

      {:ok, _view, html} = live(conn, ~p"/admin")

      assert html =~ "Live games"
      assert html =~ code
      assert html =~ "General Knowledge"
      assert html =~ "Public quizzes"
    end
  end

  describe "quizzes" do
    test "promotes, deletes and adds quizzes", %{conn: conn, quiz: quiz} do
      {:ok, view, html} = live(conn, ~p"/admin/quizzes")
      assert html =~ "Movie Night"

      view |> element("#quiz-#{quiz.id} button[phx-click=toggle_preset]") |> render_click()
      assert render(view) =~ "is now a preset"
      assert {:ok, %{source: "builtin"}} = Quizzes.fetch(quiz.id)

      view |> element("#quiz-#{quiz.id} button[phx-click=toggle_preset]") |> render_click()
      assert render(view) =~ "is a community quiz again"
      assert {:ok, %{source: "custom", slug: nil}} = Quizzes.fetch(quiz.id)

      view |> element("#quiz-#{quiz.id} button.danger") |> render_click()
      assert render(view) =~ "Deleted"
      assert Quizzes.fetch(quiz.id) == {:error, :quiz_not_found}

      json = Jason.encode!(QuizFixtures.quiz_params(%{"title" => "Pasted Preset"}))

      # A new quiz opens in the editor, which is where whoever added it is going next.
      redirect = view |> form("form[phx-submit=add_preset]", %{json: json}) |> render_submit()
      assert {:ok, %{id: id, source: "builtin"}} = Quizzes.fetch("pasted-preset")
      assert {:error, {:live_redirect, %{to: to}}} = redirect
      assert to == ~p"/admin/quizzes/#{id}/edit"

      assert {:ok, _editor, html} = follow_redirect(redirect, conn)
      assert html =~ "Pasted Preset"

      {:ok, view, _html} = live(conn, ~p"/admin/quizzes")

      view |> form("form[phx-submit=add_preset]", %{json: "nope"}) |> render_submit()
      assert render(view) =~ "valid JSON"

      view |> form("form[phx-submit=add_preset]", %{json: ~s({"title": ""})}) |> render_submit()
      assert render(view) =~ "The quiz is invalid"
    end

    test "uploads a .fazoura package, photos and all", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/quizzes")

      {:ok, binary} =
        Archive.build(
          QuizFixtures.quiz_params(%{
            "title" => "Packaged Night",
            "questions" => [
              %{
                "type" => "text_photo",
                "prompt" => "Which film?",
                "accepted_answers" => ["The Matrix"],
                "image" => %{"path" => "media/still.png", "alt" => "A still"}
              }
            ]
          }),
          %{"media/still.png" => QuizFixtures.png()}
        )

      # Choosing it is all it takes, and it lands straight in the editor: a package's
      # questions are the thing most likely to need a correction before anyone plays it.
      redirect = upload(view, "night.fazoura", binary)

      assert {:ok, quiz} = Quizzes.fetch("packaged-night")
      assert {:error, {:live_redirect, %{to: to}}} = redirect
      assert to == ~p"/admin/quizzes/#{quiz.id}/edit"

      assert {:ok, _editor, html} = follow_redirect(redirect, conn)
      assert html =~ "Which film?"
      assert {quiz.source, quiz.has_photos} == {"builtin", true}

      # The photo travelled with the document and came out an ordinary upload, so the
      # question points at a file the server can serve.
      [question] = quiz.questions
      assert question.image_alt == "A still"
      assert File.regular?(Path.join(Uploads.dir(), question.image_key))
    end

    test "says what is wrong with a package it cannot take", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/quizzes")

      assert upload(view, "broken.fazoura", "not a zip at all") =~
               "a readable .fazoura package"

      {:ok, no_photo} =
        Archive.build(
          QuizFixtures.quiz_params(%{
            "questions" => [
              %{
                "type" => "text_photo",
                "prompt" => "Which film?",
                "accepted_answers" => ["The Matrix"],
                "image" => %{"path" => "media/gone.png"}
              }
            ]
          }),
          %{}
        )

      assert upload(view, "missing.fazoura", no_photo) =~ "media/gone.png"

      # Nothing was created by either attempt: still just the one from setup.
      assert Repo.aggregate(from(q in Quiz, where: q.source == "builtin"), :count) == 1
    end

    test "there is nothing to confirm after choosing a package", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/admin/quizzes")

      # The label is the button and the input inside it is hidden, so the click opens
      # the dialog. Anything else would be a second step for a file already chosen.
      assert html =~ "Upload a package"
      assert has_element?(view, "label.button input[type=file].hidden")
      refute has_element?(view, "#add-package button")
    end

    # Choosing the file is the whole gesture: the upload starts on the choice and the
    # import happens as it finishes, so this returns whatever that produced — the page,
    # or the redirect into the editor.
    defp upload(view, name, binary) do
      view
      |> file_input("form[phx-change=validate_package]", :package, [
        %{name: name, content: binary, type: "application/zip"}
      ])
      |> render_upload(name)
    end

    test "downloads a quiz as a package", %{conn: conn, quiz: quiz} do
      {:ok, image} = Quizzes.store_image(QuizFixtures.png(), QuizFixtures.owner_key())

      {:ok, quiz} =
        Quizzes.replace(
          quiz.id,
          QuizFixtures.quiz_params(%{
            "questions" => [
              %{
                "type" => "text_photo",
                "prompt" => "Which film?",
                "accepted_answers" => ["The Matrix"],
                "image" => %{"key" => image.key}
              }
            ]
          }),
          QuizFixtures.owner_key()
        )

      {:ok, view, _html} = live(conn, ~p"/admin/quizzes")
      assert has_element?(view, "a[href='/admin/quizzes/#{quiz.id}/archive'][download]")

      response = get(conn, ~p"/admin/quizzes/#{quiz.id}/archive")
      assert response.status == 200
      assert get_resp_header(response, "content-type") == ["application/zip; charset=utf-8"]

      assert get_resp_header(response, "content-disposition") == [
               ~s(attachment; filename="#{quiz.slug || quiz.id}.fazoura")
             ]

      # What comes out is what goes back in, which is the point of having the button.
      assert {:ok, %{document: document, photos: photos}} = Archive.read(response.resp_body)
      assert document["title"] == "Movie Night"

      assert [%{"prompt" => "Which film?", "accepted_answers" => ["The Matrix"]}] =
               document["questions"]

      assert map_size(photos) == 1
    end

    test "downloading needs the dashboard's credentials", %{conn: conn, quiz: quiz} do
      assert build_conn() |> get(~p"/admin/quizzes/#{quiz.id}/archive") |> response(401)
      assert conn |> get(~p"/admin/quizzes/#{Ecto.UUID.generate()}/archive") |> response(404)
    end

    test "searches by title or tag", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/quizzes")

      html = view |> form("form[phx-change=search]", %{q: "cinema"}) |> render_change()
      assert html =~ "Movie Night"
      refute html =~ "General Knowledge"

      assert view |> form("form[phx-change=search]", %{q: "zzz"}) |> render_change() =~
               "No quizzes match"
    end
  end

  describe "the quiz editor" do
    # `form/3` reads the rendered form and merges these changes over its real values, so
    # a test sends exactly what a browser would — including the hidden fields.
    defp fields(view, changes) do
      view |> form("form[phx-submit=save]", %{"quiz" => changes}) |> render_change()
    end

    defp editor(conn, quiz) do
      {:ok, view, _html} = live(conn, ~p"/admin/quizzes/#{quiz.id}/edit")
      view
    end

    # Questions are collapsed until you open one, so a test opens it first — the fields
    # are not in the page otherwise, any more than they are for a person.
    defp open(view, cid) do
      view |> element("button[phx-click=toggle_question][phx-value-cid=#{cid}]") |> render_click()
      view
    end

    defp save(view) do
      view |> form("form[phx-submit=save]") |> render_submit()
    end

    test "opens a quiz with its questions filled in", %{conn: conn, quiz: quiz} do
      {:ok, view, html} = live(conn, ~p"/admin/quizzes/#{quiz.id}/edit")

      assert html =~ "Movie Night"
      assert html =~ "Who directed Jurassic Park?"
      assert has_element?(view, "form[phx-submit=save]")
    end

    test "a quiz that is gone sends you back to the list", %{conn: conn, quiz: quiz} do
      Fazoura.Admin.delete_quiz(quiz.id)

      assert {:error, {:live_redirect, %{to: to}}} =
               live(conn, ~p"/admin/quizzes/#{quiz.id}/edit")

      assert to == ~p"/admin/quizzes"
    end

    test "Arabic in a quiz is laid out as Arabic", %{conn: conn} do
      {:ok, quiz} =
        Quizzes.create(
          QuizFixtures.quiz_params(%{
            "title" => "ليلة الأفلام",
            "description" => "أسئلة عن السينما",
            "questions" => [
              %{
                "type" => "text",
                "prompt" => "ما هي عاصمة الجزائر؟",
                "accepted_answers" => ["الجزائر العاصمة"]
              }
            ]
          }),
          QuizFixtures.owner_key()
        )

      {:ok, view, list} = live(conn, ~p"/admin/quizzes")
      assert list =~ "ليلة الأفلام"

      # `dir="auto"` is the browser's own first-strong-character rule, so a title
      # written in Arabic reads from the right without the dashboard being an
      # Arabic dashboard.
      assert has_element?(view, "td span[dir=auto]", "ليلة الأفلام")
      assert has_element?(view, "td div[dir=auto]", "أسئلة عن السينما")

      view = conn |> editor(quiz) |> open("q1")

      assert has_element?(view, "input[name='quiz[title]'][dir=auto]")
      assert has_element?(view, "input[name='quiz[questions][q1][prompt]'][dir=auto]")

      assert has_element?(
               view,
               "textarea[name='quiz[questions][q1][accepted_answers]'][dir=auto]"
             )

      assert has_element?(view, ".preview[dir=auto]", "ما هي عاصمة الجزائر؟")
    end

    test "only the question you open renders its fields", %{conn: conn, quiz: quiz} do
      view = editor(conn, quiz)

      # Closed, the row still says which question it is.
      assert has_element?(view, "#question-q1 .preview", "Who directed Jurassic Park?")
      refute has_element?(view, "input[name='quiz[questions][q1][prompt]']")

      open(view, "q1")
      assert has_element?(view, "input[name='quiz[questions][q1][prompt]']")

      open(view, "q1")
      refute has_element?(view, "input[name='quiz[questions][q1][prompt]']")
    end

    test "a long quiz stays one question's worth of form", %{conn: conn} do
      # The length a real quiz reaches — the capitals of every country — built here
      # rather than taken from whatever ships, so the test keeps testing length.
      long =
        QuizFixtures.builtin!("world-capitals", %{
          "title" => "Capital Cities of the World",
          "questions" =>
            for index <- 1..195 do
              %{
                "type" => "text",
                "prompt" => "What is the capital of country #{index}?",
                "accepted_answers" => ["Capital #{index}"]
              }
            end
        })

      view = editor(conn, long)

      assert has_element?(view, "#question-q195")
      assert prompts_rendered(view) == 0

      open(view, "q195")
      assert prompts_rendered(view) == 1
    end

    defp prompts_rendered(view) do
      view |> render() |> then(&Regex.scan(~r/\[prompt\]/, &1)) |> length()
    end

    test "edits metadata and saves a new version", %{conn: conn, quiz: quiz} do
      view = editor(conn, quiz)

      fields(view, %{
        "title" => "Movie Night Deluxe",
        "description" => "Now with more films",
        "tags" => "cinema, classics",
        "seconds" => "45",
        "difficulty_multiplier" => "true"
      })

      assert save(view) =~ "Saved"

      {:ok, saved} = Quizzes.fetch(quiz.id)
      assert saved.title == "Movie Night Deluxe"
      assert saved.description == "Now with more films"
      assert Enum.map(saved.quiz_tags, & &1.tag) == ["cinema", "classics"]
      assert {saved.default_time_limit_ms, saved.default_difficulty_multiplier} == {45_000, true}

      # A device holding an offline copy has to be able to tell it is stale.
      assert saved.version == "1.1"
    end

    test "edits a question", %{conn: conn, quiz: quiz} do
      view = conn |> editor(quiz) |> open("q1")

      fields(view, %{
        "questions" => %{
          "q1" => %{
            "prompt" => "Capital of New Zealand?",
            "accepted_answers" => "Wellington\n  Te Whanganui-a-Tara  \n\n",
            "difficulty" => "hard",
            "seconds" => "60",
            "explanation" => "Not Auckland."
          }
        }
      })

      assert save(view) =~ "Saved"

      {:ok, saved} = Quizzes.fetch(quiz.id)
      [first | _rest] = saved.questions

      assert first.prompt == "Capital of New Zealand?"
      # One answer per line, trimmed, blank lines dropped.
      assert first.accepted_answers == ["Wellington", "Te Whanganui-a-Tara"]
      assert {first.difficulty, first.time_limit_ms} == {"hard", 60_000}
      assert first.explanation == "Not Auckland."
    end

    test "adds, moves and removes questions", %{conn: conn, quiz: quiz} do
      view = editor(conn, quiz)
      assert {:ok, %{question_count: 1}} = Quizzes.fetch(quiz.id)

      # Adding one opens it, ready to fill in.
      view |> element("button[phx-click=add_question]") |> render_click()

      fields(view, %{
        "questions" => %{"q2" => %{"prompt" => "Second?", "accepted_answers" => "Yes"}}
      })

      view |> element("button[phx-click=add_question]") |> render_click()

      fields(view, %{
        "questions" => %{"q3" => %{"prompt" => "Third?", "accepted_answers" => "Yes"}}
      })

      # q2 is closed now, and what was typed into it is still there: the working copy
      # lives in the socket, not in the rendered form.
      assert has_element?(view, "#question-q2 .preview", "Second?")

      view
      |> element("button[phx-click=move_question][phx-value-cid=q3][phx-value-by='-1']")
      |> render_click()

      view |> element("button[phx-click=remove_question][phx-value-cid=q1]") |> render_click()

      assert save(view) =~ "Saved"

      {:ok, saved} = Quizzes.fetch(quiz.id)
      # Started with q1; added q2 and q3; moved q3 above q2; dropped q1.
      assert Enum.map(saved.questions, & &1.prompt) == ["Third?", "Second?"]
    end

    test "a quiz it would refuse says why and stays put", %{conn: conn, quiz: quiz} do
      view = editor(conn, quiz)

      fields(view, %{"title" => "", "tags" => ""})
      html = save(view)

      assert html =~ "title can&#39;t be blank"
      assert html =~ "tags must be a list of 1 to 10 tags"

      # Nothing was written, and the form still holds what was typed.
      assert {:ok, %{title: "Movie Night", version: "1.0"}} = Quizzes.fetch(quiz.id)
    end

    test "a question cannot be saved empty", %{conn: conn, quiz: quiz} do
      view = conn |> editor(quiz) |> open("q1")

      fields(view, %{"questions" => %{"q1" => %{"prompt" => "", "accepted_answers" => ""}}})

      assert save(view) =~ "questions"
      assert {:ok, %{version: "1.0"}} = Quizzes.fetch(quiz.id)
    end

    test "a question with no photo does not pretend to have one", %{conn: conn, quiz: quiz} do
      view = conn |> editor(quiz) |> open("q1")
      refute has_element?(view, ".panel.question img")

      # The hidden field carries an absent photo back as "", which is not nil and was
      # read as a key — rendering <img src="/uploads/">, a broken image on every
      # question without a photo, from the first keystroke onwards.
      fields(view, %{"questions" => %{"q1" => %{"prompt" => "Still no photo"}}})

      refute has_element?(view, ".panel.question img")
      assert has_element?(view, "button[phx-click=choose_photo][phx-value-cid=q1]")
      refute has_element?(view, "button[phx-click=remove_photo][phx-value-cid=q1]")

      assert save(view) =~ "Saved"
      {:ok, saved} = Quizzes.fetch(quiz.id)
      assert [%{type: "text", image_key: nil}] = saved.questions
    end

    test "removes a photo, which makes it an ordinary text question", %{conn: conn} do
      {:ok, image} = Quizzes.store_image(QuizFixtures.png(), QuizFixtures.owner_key())

      {:ok, quiz} =
        Quizzes.create(
          QuizFixtures.quiz_params(%{
            "title" => "Photo Quiz",
            "questions" => [
              %{
                "type" => "text_photo",
                "prompt" => "Which film?",
                "accepted_answers" => ["The Matrix"],
                "image" => %{"key" => image.key, "alt" => "A still"}
              }
            ]
          }),
          QuizFixtures.owner_key()
        )

      view = conn |> editor(quiz) |> open("q1")

      # Same-origin, not the endpoint's public URL: behind a proxy — or in the local
      # stack, where that URL is https on 443 — an absolute one points somewhere the
      # browser looking at this page cannot reach, and the preview is a broken image.
      assert has_element?(view, "img[src='/uploads/#{image.key}']")

      view |> element("button[phx-click=remove_photo][phx-value-cid=q1]") |> render_click()
      assert save(view) =~ "Saved"

      {:ok, saved} = Quizzes.fetch(quiz.id)
      [question] = saved.questions

      # The type follows the photo rather than being set separately, so there is no way
      # to end up with a photo question that has no photo.
      assert {question.type, question.image_key} == {"text", nil}
      refute saved.has_photos
    end

    test "adds a photo to a question", %{conn: conn, quiz: quiz} do
      view = conn |> editor(quiz) |> open("q1")

      view |> element("button[phx-click=choose_photo][phx-value-cid=q1]") |> render_click()

      view
      |> file_input("form[phx-submit=save]", :photo, [
        %{name: "still.png", content: QuizFixtures.png(), type: "image/png"}
      ])
      |> render_upload("still.png")

      fields(view, %{"questions" => %{"q1" => %{"image_alt" => "A still"}}})
      assert save(view) =~ "Saved"

      {:ok, saved} = Quizzes.fetch(quiz.id)
      [first | _rest] = saved.questions

      assert {first.type, first.image_alt} == {"text_photo", "A still"}
      assert File.regular?(Path.join(Uploads.dir(), first.image_key))
      assert saved.has_photos
    end
  end

  describe "tags" do
    test "adds, removes, reorders and resets the suggested tags", %{conn: conn} do
      {:ok, view, html} = live(conn, ~p"/admin/tags")
      assert html =~ "pop culture"

      view |> form("form[phx-submit=add]", %{tag: "  Pub   QUIZ "}) |> render_submit()
      assert render(view) =~ "pub quiz"
      assert "pub quiz" in Settings.suggested_tags()
      assert List.last(Settings.suggested_tags()) == "pub quiz"

      view
      |> element("button[phx-click=move][phx-value-tag='pub quiz'][phx-value-by='-1']")
      |> render_click()

      tags = Settings.suggested_tags()
      assert Enum.at(tags, length(tags) - 2) == "pub quiz"

      view |> element("button[phx-click=remove][phx-value-tag='pub quiz']") |> render_click()
      refute "pub quiz" in Settings.suggested_tags()

      {:ok, _saved} = Settings.put_suggested_tags(["only this"])
      view |> element("button[phx-click=reset]") |> render_click()
      assert Settings.suggested_tags() == Tag.default_suggested()
    end

    test "rejects tags that are too long", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/tags")

      html =
        view
        |> form("form[phx-submit=add]", %{tag: String.duplicate("a", 25)})
        |> render_submit()

      assert html =~ "at most 24 characters"
    end
  end
end

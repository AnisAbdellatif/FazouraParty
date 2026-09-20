defmodule FazouraWeb.AdminLiveTest do
  use FazouraWeb.ConnCase, async: false

  import Phoenix.LiveViewTest

  import Ecto.Query

  alias Fazoura.{QuizFixtures, Quizzes, Repo, Rooms, Settings, Uploads}
  alias Fazoura.Quizzes.{Archive, Quiz, Tag}

  @username "admin"
  @password "test-admin-password"

  setup %{conn: conn} do
    Quizzes.sync_builtin!()
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
      view |> form("form[phx-submit=add_preset]", %{json: json}) |> render_submit()
      assert render(view) =~ "Added preset"
      assert {:ok, %{source: "builtin"}} = Quizzes.fetch("pasted-preset")

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

      upload(view, "night.fazoura", binary)
      view |> form("form[phx-submit=add_package]") |> render_submit()

      assert render(view) =~ "Added preset"
      assert {:ok, quiz} = Quizzes.fetch("packaged-night")
      assert {quiz.source, quiz.has_photos} == {"builtin", true}

      # The photo travelled with the document and came out an ordinary upload, so the
      # question points at a file the server can serve.
      [question] = quiz.questions
      assert question.image_alt == "A still"
      assert File.regular?(Path.join(Uploads.dir(), question.image_key))
    end

    test "says what is wrong with a package it cannot take", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/quizzes")

      upload(view, "broken.fazoura", "not a zip at all")
      view |> form("form[phx-submit=add_package]") |> render_submit()
      assert render(view) =~ "a readable .fazoura package"

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

      upload(view, "missing.fazoura", no_photo)
      view |> form("form[phx-submit=add_package]") |> render_submit()
      assert render(view) =~ "media/gone.png"

      # Nothing was created by either attempt.
      assert Repo.aggregate(from(q in Quiz, where: q.source == "builtin"), :count) == 2
    end

    test "submitting with nothing chosen says so", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/quizzes")

      view |> form("form[phx-submit=add_package]") |> render_submit()
      assert render(view) =~ "Choose a .fazoura package first"
    end

    defp upload(view, name, binary) do
      view
      |> file_input("form[phx-submit=add_package]", :package, [
        %{name: name, content: binary, type: "application/zip"}
      ])
      |> render_upload(name)

      view
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

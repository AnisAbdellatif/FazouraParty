defmodule Fazoura.AdminTest do
  # SQLite's sandbox does not support concurrent tests.
  use Fazoura.DataCase, async: false

  alias Fazoura.{Admin, QuizFixtures, Quizzes, Rooms}
  alias Fazoura.Quizzes.Quiz

  @owner QuizFixtures.owner_key()

  defp stop_room(code) do
    case Registry.lookup(Fazoura.Rooms.Registry, code) do
      [{pid, _value}] -> DynamicSupervisor.terminate_child(Fazoura.Rooms.Supervisor, pid)
      [] -> :ok
    end
  end

  describe "stats/0" do
    setup do
      Quizzes.sync_builtin!()
      {:ok, quiz} = Quizzes.create(QuizFixtures.quiz_params(), @owner)
      %{quiz: quiz}
    end

    test "counts the library" do
      stats = Admin.stats()

      assert stats.library.quizzes == 2
      assert stats.library.presets == 1
      assert stats.library.community == 1
      assert stats.library.questions == 21
      assert stats.library.photo_questions == 0
      assert stats.library.tags == 5
      assert %{tag: _, count: _} = hd(stats.top_tags)
      assert length(stats.recent) == 2
      assert Enum.all?(stats.recent, &Ecto.assoc_loaded?(&1.quiz_tags))
    end

    test "sees the rooms running right now" do
      {:ok, code, _token} = Rooms.create(QuizFixtures.pack())
      on_exit(fn -> stop_room(code) end)

      stats = Admin.stats()

      assert stats.rooms_created >= 1
      assert stats.live_rooms >= 1
      assert Map.get(stats.by_phase, :lobby, 0) >= 1

      assert %{quiz_title: "General Knowledge", phase: :lobby, players: 0, connections: 0} =
               Enum.find(stats.rooms, &(&1.code == code))
    end
  end

  describe "moderation" do
    setup do
      Quizzes.sync_builtin!()
      {:ok, quiz} = Quizzes.create(QuizFixtures.quiz_params(), @owner)
      %{quiz: quiz}
    end

    test "lists and searches by title or tag", %{quiz: quiz} do
      assert length(Admin.list_quizzes()) == 2
      assert [found] = Admin.list_quizzes(q: "  MOVIE ")
      assert found.id == quiz.id
      assert [^found] = Admin.list_quizzes(q: "cinema")
      assert Admin.list_quizzes(q: "nothing like this") == []
      assert Enum.all?(Admin.list_quizzes(), &Ecto.assoc_loaded?(&1.quiz_tags))
    end

    test "promotes a community quiz to a preset and back", %{quiz: quiz} do
      assert {:ok, preset} = Admin.set_preset(quiz.id, true)
      assert {preset.source, preset.slug} == {"builtin", "movie-night"}
      assert {:ok, %{id: id}} = Quizzes.fetch("movie-night")
      assert id == quiz.id

      assert {:ok, back} = Admin.set_preset(quiz.id, false)
      assert {back.source, back.slug} == {"custom", nil}

      assert Admin.set_preset(Ecto.UUID.generate(), true) == {:error, :quiz_not_found}
      assert Admin.set_preset("not-a-uuid", true) == {:error, :quiz_not_found}
    end

    test "preset slugs never collide" do
      {:ok, one} = Quizzes.create(QuizFixtures.quiz_params(), @owner)
      {:ok, two} = Quizzes.create(QuizFixtures.quiz_params(), @owner)

      assert {:ok, %{slug: "movie-night"}} = Admin.set_preset(one.id, true)
      assert {:ok, %{slug: "movie-night-2"}} = Admin.set_preset(two.id, true)
    end

    test "deletes presets and community quizzes alike", %{quiz: quiz} do
      {:ok, builtin} = Quizzes.fetch("general-knowledge")

      assert {:ok, _deleted} = Admin.delete_quiz(builtin.id)
      assert {:ok, _deleted} = Admin.delete_quiz(quiz.id)
      assert Admin.delete_quiz(quiz.id) == {:error, :quiz_not_found}
      assert Admin.delete_quiz("not-a-uuid") == {:error, :quiz_not_found}
      assert Repo.aggregate(Quiz, :count) == 0
    end

    test "adds a preset from a quiz document" do
      json = Jason.encode!(QuizFixtures.quiz_params(%{"title" => " Trivia Deluxe! "}))

      assert {:ok, preset} = Admin.create_preset(json)

      assert {preset.source, preset.visibility, preset.slug} ==
               {"builtin", "public", "trivia-deluxe"}

      assert {:ok, hosted} = Quizzes.fetch("trivia-deluxe")
      assert hosted.title == "Trivia Deluxe!"
      assert [%{prompt: "Who directed Jurassic Park?"}] = hosted.questions

      assert Admin.create_preset("not json") == {:error, :invalid_json}
      assert Admin.create_preset(~s(["a list"])) == {:error, :invalid_json}
      assert {:error, %Ecto.Changeset{}} = Admin.create_preset(~s({"title": ""}))
    end
  end
end

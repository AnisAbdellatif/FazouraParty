defmodule Fazoura.QuizzesTest do
  # SQLite's sandbox does not support concurrent tests.
  use Fazoura.DataCase, async: false

  alias Fazoura.QuizFixtures
  alias Fazoura.Quizzes
  alias Fazoura.Quizzes.Quiz
  alias Fazoura.Rooms.Images

  @owner "owner-key-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  @other "other-key-bbbbbbbbbbbbbbbbbbbbbbbbbbbbbb"
  # A real 1x1 PNG: uploads are validated structurally, not just by magic bytes.
  @png QuizFixtures.png()

  defp question(attrs \\ %{}) do
    Map.merge(
      %{
        "type" => "text",
        "prompt" => "  Capital of Australia?  ",
        "accepted_answers" => [" Canberra ", "", "Canberra"],
        "difficulty" => "medium"
      },
      attrs
    )
  end

  defp quiz_params(attrs \\ %{}) do
    Map.merge(
      %{
        "format_version" => 1,
        "title" => "  Movie Night ",
        "description" => "Films",
        "tags" => [" Cinema ", "cinema", "2000s"],
        "default_settings" => %{"time_limit_ms" => 20_000, "difficulty_multiplier" => true},
        "questions" => [question(), question(%{"prompt" => "Second?"})]
      },
      attrs
    )
  end

  defp errors(changeset), do: errors_on(changeset)

  defp photo_quiz(key) do
    quiz_params(%{
      "questions" => [
        question(%{"type" => "text_photo", "image" => %{"key" => key, "alt" => "A still"}})
      ]
    })
  end

  # Sweeping "two days from now" ages everything past the default 24h grace.
  defp sweep_later(days \\ 2, opts \\ []) do
    now = DateTime.add(DateTime.utc_now(), days * 86_400, :second)
    Quizzes.sweep_images(Keyword.put(opts, :now, now))
  end

  defp uploaded?(key), do: File.exists?(Path.join(Fazoura.Uploads.dir(), key))

  describe "create/2" do
    test "stores a custom quiz owned by the key, with cleaned fields" do
      assert {:ok, quiz} = Quizzes.create(quiz_params(), @owner)
      quiz = Repo.preload(quiz, [:questions, :quiz_tags], force: true)

      assert %Quiz{source: "custom", visibility: "public", title: "Movie Night"} = quiz
      assert Enum.map(quiz.quiz_tags, & &1.tag) == ["cinema", "2000s"]
      assert {quiz.question_count, quiz.has_photos} == {2, false}
      assert {quiz.default_time_limit_ms, quiz.default_difficulty_multiplier} == {20_000, true}
      assert Enum.map(quiz.questions, & &1.position) == [1, 2]
      assert hd(quiz.questions).prompt == "Capital of Australia?"
      assert hd(quiz.questions).accepted_answers == ["Canberra"]
      refute quiz.owner_key_hash == @owner
    end

    test "requires a valid owner key" do
      assert Quizzes.create(quiz_params(), nil) == {:error, :owner_key_required}
      assert Quizzes.create(quiz_params(), "short") == {:error, :owner_key_required}
    end

    test "validates the document" do
      assert {:error, cs} =
               Quizzes.create(
                 quiz_params(%{
                   "format_version" => 2,
                   "title" => " ",
                   "tags" => Enum.map(1..11, &"t#{&1}")
                 }),
                 @owner
               )

      assert %{format_version: _, title: _, tags: _} = errors(cs)

      assert {:error, cs} = Quizzes.create(quiz_params(%{"questions" => []}), @owner)
      assert %{questions: _} = errors(cs)

      assert {:error, cs} = Quizzes.create(quiz_params(%{"questions" => nil}), @owner)
      assert %{questions: ["must be a list of 1 to 1024 questions"]} = errors(cs)

      accepted =
        for index <- 1..1024 do
          question(%{"prompt" => "Question #{index}"})
        end

      assert {:ok, quiz} =
               Quizzes.create(quiz_params(%{"questions" => accepted}), @owner)

      assert quiz.question_count == 1024

      assert {:error, cs} =
               Quizzes.create(
                 quiz_params(%{"questions" => [question() | accepted]}),
                 @owner
               )

      assert %{questions: ["must be a list of 1 to 1024 questions"]} = errors(cs)

      # A real upload, so the image-ownership check passes and validation runs.
      {:ok, image} = Quizzes.store_image(@png, @owner)

      bad_questions = [
        question(%{"type" => "video"}),
        question(%{"accepted_answers" => []}),
        question(%{"accepted_answers" => [String.duplicate("a", 101)]}),
        question(%{"type" => "text_photo"}),
        question(%{"image" => %{"key" => image.key}}),
        question(%{"difficulty" => "brutal"})
      ]

      assert {:error, cs} = Quizzes.create(quiz_params(%{"questions" => bad_questions}), @owner)

      assert [
               %{type: _},
               %{accepted_answers: _},
               %{accepted_answers: ["each answer must be at most 100 characters"]},
               %{image: ["a photo question needs an image"]},
               %{image: ["text questions have no image"]},
               %{difficulty: _}
             ] = errors(cs).questions
    end

    test "tags are required, cleaned and capped" do
      assert {:ok, quiz} =
               Quizzes.create(
                 quiz_params(%{"tags" => ["  Pub   QUIZ ", "pub quiz", "80s"]}),
                 @owner
               )

      quiz = Repo.preload(quiz, :quiz_tags)
      assert Enum.map(quiz.quiz_tags, & &1.tag) == ["pub quiz", "80s"]
      assert Enum.map(quiz.quiz_tags, & &1.position) == [1, 2]

      for bad <- [[], ["  "], "movies", nil, Enum.map(1..11, &"t#{&1}")] do
        assert {:error, cs} = Quizzes.create(quiz_params(%{"tags" => bad}), @owner)
        assert %{tags: ["must be a list of 1 to 10 tags"]} = errors(cs)
      end

      assert {:error, cs} =
               Quizzes.create(quiz_params(%{"tags" => [String.duplicate("a", 25)]}), @owner)

      assert %{tags: ["each tag must be at most 24 characters"]} = errors(cs)
    end

    test "photo questions must use images uploaded by the same owner" do
      {:ok, mine} = Quizzes.store_image(@png, @owner)
      {:ok, theirs} = Quizzes.store_image(@png, @other)

      photo = fn key ->
        question(%{"type" => "text_photo", "image" => %{"key" => key, "alt" => "A still"}})
      end

      assert Quizzes.create(quiz_params(%{"questions" => [photo.(theirs.key)]}), @owner) ==
               {:error, :unknown_image}

      assert {:ok, quiz} =
               Quizzes.create(quiz_params(%{"questions" => [photo.(mine.key)]}), @owner)

      assert quiz.has_photos

      document = Quizzes.to_document(Repo.preload(quiz, :questions, force: true), owner?: true)
      assert [%{image: %{key: key, alt: "A still", url: url}}] = document.questions
      assert key == mine.key
      assert String.ends_with?(url, "/uploads/" <> key)
    end
  end

  describe "listing and reading" do
    setup do
      builtin = Enum.find(Quizzes.sync_builtin!(), &(&1.slug == "general-knowledge"))
      assert builtin != nil
      {:ok, movies} = Quizzes.create(quiz_params(), @owner)

      {:ok, science} =
        Quizzes.create(
          quiz_params(%{"title" => "Science Fair", "tags" => ["Science", "quiz night"]}),
          @other
        )

      %{builtin: builtin, movies: movies, science: science}
    end

    test "lists published quizzes, built-ins first, newest next", ctx do
      assert {:ok, quizzes, nil} = Quizzes.list()
      assert hd(quizzes).source == "builtin"
      assert ctx.builtin.id in Enum.map(quizzes, & &1.id)

      assert [ctx.movies.id, ctx.science.id] |> Enum.sort() ==
               quizzes
               |> Enum.filter(&(&1.source == "custom"))
               |> Enum.map(& &1.id)
               |> Enum.sort()
    end

    test "search by title or tag, tag filter and paging", ctx do
      assert {:ok, [%{id: id}], nil} = Quizzes.list(q: "  sCiEnce%")
      assert id == ctx.science.id
      assert {:ok, [%{id: ^id}], nil} = Quizzes.list(tag: " Science ")
      assert {:ok, [%{id: ^id}], nil} = Quizzes.list(q: "quiz night")
      assert {:ok, [%{id: movies_id}], nil} = Quizzes.list(tag: "cinema")
      assert movies_id == ctx.movies.id
      assert {:ok, [], nil} = Quizzes.list(tag: "nobody uses this")
      assert {:ok, [first], 1} = Quizzes.list(limit: 1)
      assert first.source == "builtin"
      assert {:ok, quizzes_after_first, nil} = Quizzes.list(limit: 5, offset: 1)
      assert length(quizzes_after_first) == 3
    end

    test "popular_tags counts the tags public quizzes use" do
      assert tags = Quizzes.popular_tags()
      counts = Map.new(tags, &{&1.tag, &1.count})
      assert counts["cinema"] == 1
      assert counts["general"] == 1
      assert counts["quiz night"] == 1
      assert Enum.map(tags, & &1.tag) == Enum.sort(Enum.map(tags, & &1.tag))
      assert Quizzes.popular_tags(1) |> length() == 1
    end

    test "fetch by uuid or slug", ctx do
      assert {:ok, %{id: id}} = Quizzes.fetch(ctx.movies.id)
      assert id == ctx.movies.id
      assert {:ok, %{id: builtin_id}} = Quizzes.fetch("general-knowledge")
      assert builtin_id == ctx.builtin.id
      assert {:error, :quiz_not_found} = Quizzes.fetch("missing")
      assert {:error, :quiz_not_found} = Quizzes.fetch(nil)
    end

    test "documents include answers only for the publisher", ctx do
      {:ok, quiz} = Quizzes.fetch(ctx.movies.id)
      assert Quizzes.owner?(quiz, @owner)
      refute Quizzes.owner?(quiz, @other)
      refute Map.has_key?(Quizzes.to_document(quiz), :questions)

      assert %{is_owner: true, questions: [%{accepted_answers: ["Canberra"]} | _]} =
               Quizzes.to_document(quiz, owner?: true)

      refute Map.has_key?(Quizzes.to_document(quiz, owner?: true, questions: false), :questions)
    end
  end

  describe "replace/3 and delete/2" do
    setup do
      {:ok, quiz} = Quizzes.create(quiz_params(), @owner)
      %{quiz: quiz}
    end

    test "publisher replaces the quiz and all its questions", %{quiz: quiz} do
      params =
        quiz_params(%{"title" => "Renamed", "questions" => [question(%{"prompt" => "Only one"})]})

      assert {:error, :quiz_not_found} = Quizzes.replace(quiz.id, params, @other)
      assert {:ok, updated} = Quizzes.replace(quiz.id, params, @owner)
      updated = Repo.preload(updated, :questions, force: true)
      assert {updated.title, updated.question_count} == {"Renamed", 1}
      assert updated.version == "1.1"
      assert Enum.map(updated.questions, & &1.prompt) == ["Only one"]

      assert {:error, %Ecto.Changeset{}} =
               Quizzes.replace(quiz.id, quiz_params(%{"questions" => []}), @owner)

      {:ok, unchanged} = Quizzes.fetch(quiz.id)
      assert unchanged.question_count == 1
    end

    test "publisher unpublishes; built-ins can't be changed through the API", %{quiz: quiz} do
      builtin = Enum.find(Quizzes.sync_builtin!(), &(&1.slug == "general-knowledge"))
      assert builtin != nil
      assert {:error, :quiz_not_found} = Quizzes.delete(builtin.id, @owner)
      assert {:error, :quiz_not_found} = Quizzes.delete(quiz.id, @other)
      assert :ok = Quizzes.delete(quiz.id, @owner)
      assert {:error, :quiz_not_found} = Quizzes.fetch(quiz.id)
    end
  end

  describe "inline_pack/1 (private quizzes)" do
    test "builds a pack without storing anything, photos held in memory" do
      params =
        quiz_params(%{
          "questions" => [
            question(),
            question(%{
              "type" => "text_photo",
              "image" => %{"data" => Base.encode64(@png), "alt" => "A still", "key" => "ignored"}
            })
          ]
        })

      assert {:ok, pack, [key]} = Quizzes.inline_pack(params)
      assert Repo.aggregate(Quiz, :count) == 0

      assert {pack.id, pack.title, pack.default_time_limit_ms} ==
               {"inline", "Movie Night", 20_000}

      assert [%{id: "q1", image_url: nil}, %{id: "q2", image_url: url}] = pack.questions
      assert hd(pack.questions).accepted_answers == ["Canberra"]
      assert String.ends_with?(url, "/api/room-images/" <> key)
      assert String.ends_with?(key, ".png")
      assert Images.fetch(key) == {:ok, "image/png", @png}

      Images.delete([key])
      assert Images.fetch(key) == :error
    end

    test "validates the document and the photos" do
      assert {:error, %Ecto.Changeset{}} = Quizzes.inline_pack(quiz_params(%{"questions" => []}))
      assert {:error, %Ecto.Changeset{}} = Quizzes.inline_pack("nope")

      photo = fn data ->
        quiz_params(%{
          "questions" => [question(%{"type" => "text_photo", "image" => %{"data" => data}})]
        })
      end

      assert Quizzes.inline_pack(photo.("not base64!")) == {:error, :unsupported_image}
      assert Quizzes.inline_pack(photo.(Base.encode64("GIF89a"))) == {:error, :unsupported_image}

      too_big = Base.encode64(@png <> :binary.copy(<<0>>, Fazoura.Uploads.max_bytes()))
      assert Quizzes.inline_pack(photo.(too_big)) == {:error, :image_too_large}

      # A stored image key without data is not a photo for an inline quiz.
      no_data =
        quiz_params(%{
          "questions" => [question(%{"type" => "text_photo", "image" => %{"key" => "x.png"}})]
        })

      assert {:error, cs} = Quizzes.inline_pack(no_data)
      assert [%{image: ["a photo question needs an image"]}] = errors(cs).questions
    end
  end

  describe "built-ins and packs" do
    test "sync_builtin! is idempotent and loads the 20-question General Knowledge quiz" do
      first = Enum.find(Quizzes.sync_builtin!(), &(&1.slug == "general-knowledge"))
      again = Enum.find(Quizzes.sync_builtin!(), &(&1.slug == "general-knowledge"))
      assert first.id == again.id
      assert Repo.aggregate(Quiz, :count) == 2

      {:ok, quiz} = Quizzes.fetch("general-knowledge")
      assert {quiz.source, quiz.visibility, quiz.question_count} == {"builtin", "public", 20}

      assert Enum.map(quiz.questions, & &1.difficulty) |> Enum.uniq() |> Enum.sort() ==
               ["easy", "hard", "medium"]
    end

    test "to_pack snapshots questions with defaults and photo urls" do
      {:ok, image} = Quizzes.store_image(@png, @owner)

      params =
        quiz_params(%{
          "questions" => [
            question(),
            question(%{"type" => "text_photo", "image" => %{"key" => image.key}})
          ]
        })

      {:ok, quiz} = Quizzes.create(params, @owner)
      {:ok, quiz} = Quizzes.fetch(quiz.id)
      pack = Quizzes.to_pack(quiz)

      assert {pack.title, pack.default_time_limit_ms, pack.default_difficulty_multiplier} ==
               {"Movie Night", 20_000, true}

      assert [%{image_url: nil, time_limit_ms: 20_000, difficulty: "medium"}, %{image_url: url}] =
               pack.questions

      assert String.ends_with?(url, image.key)

      game = Fazoura.Game.new("ROOM42", pack)

      assert game.settings == %{
               question_count: 2,
               time_limit_ms: 20_000,
               difficulty_multiplier: true,
               difficulties: ["medium"],
               available_difficulties: ["medium"]
             }
    end
  end

  describe "store_image/2" do
    test "detects the type from content and enforces the size limit" do
      assert {:ok, %{content_type: "image/png", key: key}} = Quizzes.store_image(@png, @owner)
      assert String.ends_with?(key, ".png")
      assert File.exists?(Path.join(Fazoura.Uploads.dir(), key))

      assert {:ok, %{content_type: "image/jpeg"}} =
               Quizzes.store_image(QuizFixtures.jpeg(), @owner)

      assert {:ok, %{content_type: "image/webp"}} =
               Quizzes.store_image(QuizFixtures.webp(), @owner)

      assert Quizzes.store_image("GIF89a...", @owner) == {:error, :unsupported_image}

      # Magic bytes alone are no longer enough: the header must be well-formed too.
      assert Quizzes.store_image(<<0xFF, 0xD8, 0xFF, 0xE0, "jpeg">>, @owner) ==
               {:error, :unsupported_image}

      assert Quizzes.store_image(@png, nil) == {:error, :owner_key_required}

      too_big = @png <> :binary.copy(<<0>>, Fazoura.Uploads.max_bytes())
      assert Quizzes.store_image(too_big, @owner) == {:error, :image_too_large}
    end
  end

  describe "sweep_images/1" do
    # Its own uploads directory, so counts aren't thrown off by other tests' files.
    setup %{tmp_dir: tmp_dir} do
      previous = Application.fetch_env!(:fazoura, :uploads_dir)
      Application.put_env(:fazoura, :uploads_dir, tmp_dir)
      on_exit(fn -> Application.put_env(:fazoura, :uploads_dir, previous) end)
    end

    @tag :tmp_dir
    test "collects an upload no quiz ever used" do
      {:ok, image} = Quizzes.store_image(@png, @owner)

      assert %{images: 1, files: 0, bytes: bytes} = sweep_later()
      assert bytes == byte_size(@png)
      refute uploaded?(image.key)
      assert Repo.aggregate(Fazoura.Quizzes.Image, :count) == 0
    end

    @tag :tmp_dir
    test "keeps an upload a published quiz still points at" do
      {:ok, image} = Quizzes.store_image(@png, @owner)
      {:ok, _quiz} = Quizzes.create(photo_quiz(image.key), @owner)

      assert %{images: 0, files: 0} = sweep_later()
      assert uploaded?(image.key)
    end

    @tag :tmp_dir
    test "keeps a fresh upload: its quiz may still be being written" do
      {:ok, image} = Quizzes.store_image(@png, @owner)

      assert %{images: 0} = Quizzes.sweep_images()
      assert uploaded?(image.key)

      # The grace is what protects it, not anything about the image itself.
      assert %{images: 1} = sweep_later(2, grace_seconds: 0)
      refute uploaded?(image.key)
    end

    @tag :tmp_dir
    test "collects the photos of an unpublished quiz" do
      {:ok, image} = Quizzes.store_image(@png, @owner)
      {:ok, quiz} = Quizzes.create(photo_quiz(image.key), @owner)

      assert Quizzes.delete(quiz.id, @owner) == :ok
      assert %{images: 1} = sweep_later()
      refute uploaded?(image.key)
    end

    @tag :tmp_dir
    test "collects the photo a replacement dropped" do
      {:ok, dropped} = Quizzes.store_image(@png, @owner)
      {:ok, kept} = Quizzes.store_image(@png, @owner)
      {:ok, quiz} = Quizzes.create(photo_quiz(dropped.key), @owner)

      assert {:ok, _replaced} = Quizzes.replace(quiz.id, photo_quiz(kept.key), @owner)
      assert %{images: 1} = sweep_later()
      refute uploaded?(dropped.key)
      assert uploaded?(kept.key)
    end

    @tag :tmp_dir
    test "removes a file the database never heard of", %{tmp_dir: tmp_dir} do
      stray = Path.join(tmp_dir, "orphan.png")
      File.write!(stray, @png)

      assert %{images: 0, files: 1} = sweep_later()
      refute File.exists?(stray)
    end
  end
end

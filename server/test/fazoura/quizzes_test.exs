defmodule Fazoura.QuizzesTest do
  # SQLite's sandbox does not support concurrent tests.
  use Fazoura.DataCase, async: false

  alias Fazoura.{Admin, QuizFixtures, Quizzes}
  alias Fazoura.Quizzes.{Archive, Image, Quiz}
  alias Fazoura.Rooms.Images
  alias Fazoura.Uploads

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
      builtin = QuizFixtures.builtin!("general-knowledge")
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
      # The three this test made, less the first page. The count comes from the setup
      # rather than from however many quizzes happen to ship with the server.
      assert {:ok, quizzes_after_first, nil} = Quizzes.list(limit: 5, offset: 1)
      assert length(quizzes_after_first) == 2
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
    test "a field cleared to an empty string is reported, not a crash" do
      {:ok, quiz} = Quizzes.create(quiz_params(), @owner)

      # Ecto replaces an emptied field with the schema default — nil — so a changeset
      # that trims it has to cope with one. This used to raise, which meant a 500.
      assert {:error, changeset} =
               Quizzes.replace(
                 quiz.id,
                 quiz_params(%{"title" => "", "questions" => [question(%{"prompt" => ""})]}),
                 @owner
               )

      assert %{title: ["can't be blank"]} = errors(changeset)
      assert [%{prompt: ["can't be blank"]}] = errors(changeset).questions
    end

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
      builtin = QuizFixtures.builtin!("general-knowledge")
      assert {:error, :quiz_not_found} = Quizzes.delete(builtin.id, @owner)
      assert {:error, :quiz_not_found} = Quizzes.delete(quiz.id, @other)
      assert :ok = Quizzes.delete(quiz.id, @owner)
      assert {:error, :quiz_not_found} = Quizzes.fetch(quiz.id)
    end
  end

  describe "inline_pack/2 (private quizzes)" do
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

      assert {:ok, pack, [key], bytes} = Quizzes.inline_pack(params)
      assert bytes > 0
      assert Repo.aggregate(Quiz, :count) == 0

      assert {pack.titles, pack.default_time_limit_ms} == {["Movie Night"], 20_000}

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

  describe "built-in presets" do
    test "sync_builtin! loads a JSON document as a public preset, idempotently" do
      # Its own directory, not `priv/quizzes`: what ships with the server is content, and
      # a test that asserts on it fails the day someone changes what ships.
      dir = preset_dir(nil)

      [first] = Quizzes.sync_builtin!(dir)
      [again] = Quizzes.sync_builtin!(dir)

      assert first.id == again.id
      assert Repo.aggregate(Quiz, :count) == 1

      {:ok, quiz} = Quizzes.fetch("film-night")
      assert {quiz.slug, quiz.source, quiz.visibility} == {"film-night", "builtin", "public"}
    end

    test "a preset photo becomes an ordinary upload" do
      dir = preset_dir(%{"path" => "media/still.png", "alt" => "A still"})

      [quiz] = Quizzes.sync_builtin!(dir)
      {:ok, quiz} = Quizzes.fetch(quiz.id)
      [question] = quiz.questions

      # Nothing about it is special once it is in: a key, a file in the uploads
      # directory and a row in `images`, like a photo any device published.
      assert question.image_key
      assert question.image_alt == "A still"
      assert File.regular?(Path.join(Uploads.dir(), question.image_key))
      assert Repo.get_by(Image, key: question.image_key)
      assert quiz.has_photos

      document = Quizzes.to_document(quiz, owner?: true)
      assert [%{image: %{url: url}}] = document.questions
      assert String.ends_with?(url, "/uploads/" <> question.image_key)
    end

    test "re-syncing reuses the same file instead of piling up copies" do
      dir = preset_dir(%{"path" => "media/still.png"})

      [first] = Quizzes.sync_builtin!(dir)
      [again] = Quizzes.sync_builtin!(dir)

      {:ok, first} = Quizzes.fetch(first.id)
      {:ok, again} = Quizzes.fetch(again.id)

      # A random key would write a new file every deploy and leave the last one
      # for the sweeper; the key comes from the bytes instead.
      assert hd(first.questions).image_key == hd(again.questions).image_key
      assert Repo.aggregate(from(i in Image), :count) == 1
    end

    test "a preset photo the repository lost stops the sync" do
      dir = preset_dir(%{"path" => "media/missing.png"})
      File.rm!(Path.join(dir, "media/still.png"))

      # Loudly, because this runs on every deploy: a preset with a hole in it
      # should stop the release rather than reach a party.
      assert_raise ArgumentError, ~r/missing\.png/, fn -> Quizzes.sync_builtin!(dir) end
    end

    test "a preset photo cannot be read from outside its own directory" do
      dir = preset_dir(%{"path" => "../../../etc/passwd"})

      assert_raise ArgumentError, ~r/outside/, fn -> Quizzes.sync_builtin!(dir) end
    end

    test "a preset photo that is not an image is refused" do
      dir = preset_dir(%{"path" => "media/still.png"})
      File.write!(Path.join(dir, "media/still.png"), "GIF89a not one of ours")

      assert_raise ArgumentError, ~r/refused/, fn -> Quizzes.sync_builtin!(dir) end
    end

    defp preset_dir(image) do
      dir = Path.join(System.tmp_dir!(), "fazoura_preset_#{System.unique_integer([:positive])}")
      File.mkdir_p!(Path.join(dir, "media"))
      on_exit(fn -> File.rm_rf!(dir) end)

      File.write!(Path.join(dir, "media/still.png"), @png)

      question =
        if image do
          %{
            "type" => "text_photo",
            "prompt" => "Which film?",
            "accepted_answers" => ["The Matrix"],
            "image" => image
          }
        else
          %{"type" => "text", "prompt" => "Which film?", "accepted_answers" => ["The Matrix"]}
        end

      File.write!(
        Path.join(dir, "film-night.json"),
        Jason.encode!(
          QuizFixtures.quiz_params(%{"title" => "Film Night", "questions" => [question]})
        )
      )

      dir
    end
  end

  describe "seeding from a packages directory" do
    defp packages_dir(files) do
      dir = Path.join(System.tmp_dir!(), "fazoura_packages_#{System.unique_integer([:positive])}")
      File.mkdir_p!(dir)
      on_exit(fn -> File.rm_rf!(dir) end)

      for {name, binary} <- files, do: File.write!(Path.join(dir, name), binary)
      dir
    end

    defp package_binary(attrs \\ %{}, photos \\ %{}) do
      {:ok, binary} = Archive.build(quiz_params(attrs), photos)
      binary
    end

    test "a package in the directory becomes a preset named by its filename" do
      dir =
        packages_dir(%{
          "film-night.fazoura" =>
            package_binary(
              %{
                "title" => "Film Night",
                "questions" => [
                  question(%{
                    "type" => "text_photo",
                    "prompt" => "Which film?",
                    "image" => %{"path" => "media/still.png", "alt" => "A still"}
                  })
                ]
              },
              %{"media/still.png" => @png}
            )
        })

      assert [quiz] = Quizzes.sync_packages!(dir)
      assert {:ok, quiz} = Quizzes.fetch("film-night")

      # Hostable by name, like any other preset, and its photo arrived with it — there
      # was nothing to publish first.
      assert {quiz.title, quiz.slug, quiz.source, quiz.visibility} ==
               {"Film Night", "film-night", "builtin", "public"}

      [photo] = quiz.questions
      assert photo.image_alt == "A still"
      assert File.regular?(Path.join(Uploads.dir(), photo.image_key))
    end

    test "re-running updates the quiz it already made" do
      dir = packages_dir(%{"film-night.fazoura" => package_binary(%{"title" => "Film Night"})})

      [first] = Quizzes.sync_packages!(dir)
      [again] = Quizzes.sync_packages!(dir)

      assert first.id == again.id
      assert Repo.aggregate(from(q in Quiz, where: q.source == "builtin"), :count) == 1

      # Replacing the file replaces the quiz rather than adding a second one.
      File.write!(
        Path.join(dir, "film-night.fazoura"),
        package_binary(%{"title" => "Film Night Deluxe"})
      )

      [updated] = Quizzes.sync_packages!(dir)
      assert updated.id == first.id
      assert updated.title == "Film Night Deluxe"
      assert Repo.aggregate(from(q in Quiz, where: q.source == "builtin"), :count) == 1
    end

    test "every package in the directory is loaded, in a fixed order" do
      dir =
        packages_dir(%{
          "b-night.fazoura" => package_binary(%{"title" => "B"}),
          "a-night.fazoura" => package_binary(%{"title" => "A"}),
          "notes.txt" => "not a package, and not read"
        })

      assert Enum.map(Quizzes.sync_packages!(dir), & &1.slug) == ["a-night", "b-night"]
    end

    test "a directory that is not there is simply no packages" do
      assert Quizzes.sync_packages!(Path.join(System.tmp_dir!(), "fazoura_no_such_dir")) == []
    end

    test "the shipped directory and the drop directory are both read" do
      shipped = packages_dir(%{"shipped.fazoura" => package_binary(%{"title" => "Shipped"})})
      dropped = packages_dir(%{"dropped.fazoura" => package_binary(%{"title" => "Dropped"})})

      Application.put_env(:fazoura, :packages_dir, shipped)
      Application.put_env(:fazoura, :packages_drop_dir, dropped)

      on_exit(fn ->
        Application.put_env(:fazoura, :packages_dir, Path.join(System.tmp_dir!(), "none"))
        Application.put_env(:fazoura, :packages_drop_dir, nil)
      end)

      # A package committed to the repo has to seed a deploy, exactly as a JSON built-in
      # does; the drop directory is for adding one without rebuilding.
      assert Enum.map(Quizzes.sync_packages!(), & &1.slug) == ["shipped", "dropped"]
      assert Quizzes.packages_dirs() == [shipped, dropped]
    end

    test "a dropped package can correct a shipped one of the same slug" do
      shipped =
        packages_dir(%{"film-night.fazoura" => package_binary(%{"title" => "Film Night"})})

      dropped =
        packages_dir(%{"film-night.fazoura" => package_binary(%{"title" => "Film Night Fixed"})})

      Application.put_env(:fazoura, :packages_dir, shipped)
      Application.put_env(:fazoura, :packages_drop_dir, dropped)

      on_exit(fn ->
        Application.put_env(:fazoura, :packages_dir, Path.join(System.tmp_dir!(), "none"))
        Application.put_env(:fazoura, :packages_drop_dir, nil)
      end)

      # The drop directory is read last, which is what makes it the only way to fix a
      # shipped quiz without a deploy.
      Quizzes.sync_packages!()
      assert {:ok, quiz} = Quizzes.fetch("film-night")
      assert quiz.title == "Film Night Fixed"
      assert Repo.aggregate(from(q in Quiz, where: q.source == "builtin"), :count) == 1
    end

    test "a package that cannot be read stops the sync" do
      dir = packages_dir(%{"broken.fazoura" => "not a zip at all"})

      # This runs on a deploy: a quiz someone put here going quietly missing is worse
      # than a release that stops.
      assert_raise ArgumentError, ~r/broken\.fazoura was refused/, fn ->
        Quizzes.sync_packages!(dir)
      end
    end
  end

  describe "reading a .fazoura package" do
    defp package(questions, photos) do
      {:ok, binary} =
        Archive.build(quiz_params(%{"questions" => questions}), photos)

      binary
    end

    test "photos in the package become ordinary uploads the questions point at" do
      binary =
        package(
          [
            question(%{
              "type" => "text_photo",
              "prompt" => "Which film?",
              "image" => %{"path" => "media/still.png", "alt" => "A still"}
            })
          ],
          %{"media/still.png" => @png}
        )

      assert {:ok, params} = Quizzes.read_archive(binary)
      assert [%{"image" => image}] = params["questions"]

      # The path is gone: from here on this is a photo like any other, and nothing
      # downstream can tell it arrived in a ZIP.
      assert %{"key" => key, "alt" => "A still"} = image
      refute Map.has_key?(image, "path")
      assert File.regular?(Path.join(Uploads.dir(), key))
      assert Repo.get_by(Image, key: key)
    end

    test "the same photo twice is stored once" do
      binary =
        package(
          [
            question(%{"type" => "text_photo", "image" => %{"path" => "media/a.png"}}),
            question(%{"type" => "text_photo", "image" => %{"path" => "media/b.png"}})
          ],
          %{"media/a.png" => @png, "media/b.png" => @png}
        )

      assert {:ok, params} = Quizzes.read_archive(binary)

      assert [%{"image" => %{"key" => first}}, %{"image" => %{"key" => second}}] =
               params["questions"]

      # The key comes from the bytes, so two names for one photo collapse.
      assert first == second
      assert Repo.aggregate(from(i in Image), :count) == 1
    end

    test "a manifest asking for a photo the package does not carry" do
      binary =
        package(
          [question(%{"type" => "text_photo", "image" => %{"path" => "media/gone.png"}})],
          %{}
        )

      assert Quizzes.read_archive(binary) ==
               {:error, {:not_in_the_package, "media/gone.png"}}
    end

    test "a photo that is not an image the server accepts" do
      binary =
        package(
          [question(%{"type" => "text_photo", "image" => %{"path" => "media/still.png"}})],
          %{"media/still.png" => "GIF89a not one of ours"}
        )

      assert Quizzes.read_archive(binary) ==
               {:error, {:unsupported_image, "media/still.png"}}
    end

    test "a quiz with no photos at all comes through untouched" do
      binary = package([question()], %{})

      assert {:ok, params} = Quizzes.read_archive(binary)
      assert params["title"] == "  Movie Night "
      assert [%{"prompt" => _prompt}] = params["questions"]
    end

    test "what archive/1 writes is what read_archive/1 reads" do
      {:ok, image} = Quizzes.store_image(@png, @owner)

      {:ok, quiz} =
        Quizzes.create(
          quiz_params(%{
            "questions" => [
              question(%{"type" => "text_photo", "image" => %{"key" => image.key}})
            ]
          }),
          @owner
        )

      {:ok, quiz} = Quizzes.fetch(quiz.id)
      {:ok, binary} = Quizzes.archive(quiz)

      # A quiz can be exported from one server and taken into another, which is the
      # whole point of the format (QUIZ_FORMAT.md §5.3b).
      assert {:ok, params} = Quizzes.read_archive(binary)
      assert {:ok, restored} = Admin.create_preset(params)
      {:ok, restored} = Quizzes.fetch(restored.id)

      assert Enum.map(restored.questions, & &1.prompt) ==
               Enum.map(quiz.questions, & &1.prompt)

      assert Enum.map(restored.questions, & &1.accepted_answers) ==
               Enum.map(quiz.questions, & &1.accepted_answers)

      # The photo comes back as a new upload rather than the publisher's: the package
      # carries bytes, not a claim on a row someone else owns. Same picture, though.
      restored_key = hd(restored.questions).image_key
      refute restored_key == image.key
      assert Uploads.read(restored_key) == {:ok, @png}
    end
  end

  describe "packs" do
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

      assert {pack.titles, pack.default_time_limit_ms, pack.default_difficulty_multiplier} ==
               {["Movie Night"], 20_000, true}

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

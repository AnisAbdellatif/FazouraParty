defmodule FazouraWeb.SelectQuizTest do
  @moduledoc """
  `host_select_quiz`: what a host may choose to play, and what the room does
  with it (PROTOCOL.md §6.4).

  The happy path over several quizzes is replayed from
  `protocol/fixtures/scenarios/multiple_quizzes.json` against both hosts; what
  is left here is everything that only Cloud can do — resolving stored quizzes
  by id, and mixing those with documents the host keeps on its device.
  """

  use FazouraWeb.ChannelCase, async: false

  alias Fazoura.{QuizFixtures, Quizzes, Rooms}

  # Resolving a `quiz_id` reads the database from the room's own process, so
  # the sandbox has to be shared with it (AGENTS.md §5: DB tests are
  # `async: false` under SQLite).
  setup tags do
    Fazoura.DataCase.setup_sandbox(tags)
    :ok
  end

  setup do
    {:ok, code, host_token} = Rooms.create(%Fazoura.Game.Pack{titles: [], questions: []})
    {:ok, _, socket} = join_room(code, %{"host_token" => host_token})
    assert_push "state", %{}
    %{code: code, socket: socket}
  end

  defp join_room(code, payload) do
    socket(FazouraWeb.UserSocket, nil, %{})
    |> join(
      FazouraWeb.RoomChannel,
      "room:" <> code,
      Map.put(payload, "protocol_version", Fazoura.Game.protocol_major())
    )
  end

  defp select(socket, quizzes) do
    ref = push(socket, "host_select_quiz", %{"quizzes" => quizzes})
    ref
  end

  defp stored!(title, prompts) do
    params =
      QuizFixtures.quiz_params(%{
        "title" => title,
        "questions" =>
          for prompt <- prompts do
            %{"type" => "text", "prompt" => prompt, "accepted_answers" => [prompt]}
          end
      })

    {:ok, quiz} = Quizzes.create(params, QuizFixtures.owner_key())
    quiz
  end

  defp inline(title, prompts) do
    %{
      "quiz" =>
        QuizFixtures.quiz_params(%{
          "title" => title,
          "questions" =>
            for prompt <- prompts do
              %{"type" => "text", "prompt" => prompt, "accepted_answers" => [prompt]}
            end
        })
    }
  end

  describe "the selection" do
    test "one stored quiz plays on its own", %{socket: socket} do
      quiz = stored!("Science", ["Sci one?", "Sci two?"])

      ref = select(socket, [%{"quiz_id" => quiz.id}])
      assert_reply ref, :ok, %{}
      assert_push "state", %{pack_titles: ["Science"], question_count: 2}
    end

    test "a stored quiz and a private one play as one pool", %{socket: socket} do
      quiz = stored!("Science", ["Sci one?", "Sci two?"])

      ref = select(socket, [%{"quiz_id" => quiz.id}, inline("Kitchen Table", ["Ours?"])])
      assert_reply ref, :ok, %{}

      assert_push "state", %{
        pack_titles: ["Science", "Kitchen Table"],
        question_count: 3,
        settings: %{max_question_count: 3}
      }
    end

    test "the order the host chose is the order of the titles", %{socket: socket} do
      ref = select(socket, [inline("B", ["b?"]), inline("A", ["a?"]), inline("C", ["c?"])])
      assert_reply ref, :ok, %{}
      assert_push "state", %{pack_titles: ["B", "A", "C"]}
    end

    test "lobby defaults come from the first quiz", %{socket: socket} do
      slow = %{
        "quiz" =>
          QuizFixtures.quiz_params(%{
            "title" => "Slow",
            "default_settings" => %{"time_limit_ms" => 90_000, "difficulty_multiplier" => true},
            "questions" => [
              %{"type" => "text", "prompt" => "?", "accepted_answers" => ["a"]}
            ]
          })
      }

      ref = select(socket, [slow, inline("Fast", ["b?"])])
      assert_reply ref, :ok, %{}

      assert_push "state", %{
        settings: %{time_limit_ms: 90_000, difficulty_multiplier: true}
      }
    end

    test "selecting again replaces the whole selection", %{socket: socket} do
      ref = select(socket, [inline("First", ["a?"]), inline("Second", ["b?"])])
      assert_reply ref, :ok, %{}
      assert_push "state", %{pack_titles: ["First", "Second"]}

      ref = select(socket, [inline("Third", ["c?"])])
      assert_reply ref, :ok, %{}
      assert_push "state", %{pack_titles: ["Third"], question_count: 1}
    end

    test "ten quizzes are allowed, eleven are not", %{socket: socket} do
      ten = for i <- 1..10, do: inline("Quiz #{i}", ["q#{i}?"])

      ref = select(socket, ten)
      assert_reply ref, :ok, %{}
      assert_push "state", %{question_count: 10}

      ref = select(socket, ten ++ [inline("One too many", ["x?"])])
      assert_reply ref, :error, %{code: "invalid_quiz"}
    end
  end

  describe "refusals" do
    test "an empty or malformed selection is invalid_quiz", %{socket: socket} do
      for payload <- [
            %{"quizzes" => []},
            %{"quizzes" => "science"},
            %{"quizzes" => [%{}]},
            %{"quizzes" => [%{"quiz" => "not a document"}]},
            %{"quiz_id" => "the old single shape"},
            %{}
          ] do
        ref = push(socket, "host_select_quiz", payload)
        assert_reply ref, :error, %{code: "invalid_quiz"}, 1_000
      end
    end

    test "an unknown id is quiz_not_found, and nothing is selected", %{socket: socket} do
      quiz = stored!("Science", ["Sci one?"])

      ref = select(socket, [%{"quiz_id" => quiz.id}, %{"quiz_id" => Ecto.UUID.generate()}])
      assert_reply ref, :error, %{code: "quiz_not_found"}

      refute_push "state", %{}
    end

    test "a quiz with no playable questions cannot be selected", %{socket: socket} do
      ref =
        select(socket, [
          %{"quiz" => QuizFixtures.quiz_params(%{"title" => "Hollow", "questions" => []})}
        ])

      # The document itself is refused before the pool is ever built, because
      # a quiz must carry at least one question (QUIZ_FORMAT.md §2.2).
      assert_reply ref, :error, %{code: "invalid_quiz"}
    end

    test "only the host may choose", %{code: code, socket: socket} do
      {:ok, _, player} = join_room(code, %{"display_name" => "Sam"})

      ref = select(player, [inline("Theirs", ["a?"])])
      assert_reply ref, :error, %{code: "not_host"}

      ref = select(socket, [inline("Mine", ["a?"])])
      assert_reply ref, :ok, %{}
    end

    test "the selection cannot change once the game is under way", %{socket: socket} do
      ref = select(socket, [inline("Science", ["a?"])])
      assert_reply ref, :ok, %{}

      ref = push(socket, "host_next", %{})
      assert_reply ref, :ok, %{}

      ref = select(socket, [inline("Too late", ["b?"])])
      assert_reply ref, :error, %{code: "invalid_phase"}, 1_000
    end
  end

  describe "photo budget" do
    # A photo every per-image check accepts, and how many it takes to pass the
    # per-room total.
    defp under_image_cap, do: div(Fazoura.Uploads.max_bytes(), 2)
    defp photo(bytes), do: Base.encode64(QuizFixtures.png_of_size(bytes))

    defp photo_quiz(title, count, bytes) do
      %{
        "quiz" =>
          QuizFixtures.quiz_params(%{
            "title" => title,
            "questions" =>
              for i <- 1..count do
                %{
                  "type" => "text_photo",
                  "prompt" => "Question #{i}?",
                  "accepted_answers" => ["a"],
                  "image" => %{"data" => photo(bytes)}
                }
              end
          })
      }
    end

    test "the total is bounded across the selection, not per quiz", %{socket: socket} do
      # Each quiz is comfortably inside the room cap on its own; together they
      # are over it. Counting per quiz would let a selection hold ten times what
      # one room is allowed (QUIZ_FORMAT.md §5.7).
      per_quiz = photo_quiz("Heavy", 2, under_image_cap())

      quizzes =
        List.duplicate(per_quiz, ceil(Quizzes.max_inline_bytes() / (2 * under_image_cap())) + 1)

      ref = select(socket, [per_quiz])
      assert_reply ref, :ok, %{}

      # Said as what it is, since it is something the host can do something about.
      ref = select(socket, quizzes)
      assert_reply ref, :error, %{code: "quiz_too_large"}, 2_000
    end

    test "a selection that fails part way leaves no photos behind", %{socket: socket} do
      before = :ets.info(Fazoura.Rooms.Images, :size)

      # The first quiz resolves and puts its photo in memory; the second names a
      # quiz that does not exist, so the whole selection is refused and nothing
      # will ever attach — or collect — that photo.
      ref =
        select(socket, [
          photo_quiz("Resolves", 1, 1000),
          %{"quiz_id" => Ecto.UUID.generate()}
        ])

      assert_reply ref, :error, %{code: "quiz_not_found"}, 2_000
      assert :ets.info(Fazoura.Rooms.Images, :size) == before
    end

    test "photos of an accepted selection are kept", %{socket: socket} do
      before = :ets.info(Fazoura.Rooms.Images, :size)

      ref = select(socket, [photo_quiz("One", 1, 1000), photo_quiz("Two", 1, 1000)])
      assert_reply ref, :ok, %{}

      assert :ets.info(Fazoura.Rooms.Images, :size) == before + 2
    end
  end

  describe "the pool" do
    test "questions keep their own prompts and ids stay unique across quizzes", %{
      socket: socket
    } do
      # Both quizzes number their questions from 1, which is the collision the
      # merge exists to prevent: clients tell questions apart by id (§6.4).
      ref = select(socket, [inline("One", ["From one?"]), inline("Two", ["From two?"])])
      assert_reply ref, :ok, %{}
      assert_push "state", %{}

      ids = room_question_ids(socket)
      assert length(ids) == 2
      assert length(Enum.uniq(ids)) == 2
    end
  end

  defp room_question_ids(socket) do
    [{pid, _}] = Registry.lookup(Fazoura.Rooms.Registry, socket.assigns.room_code)
    :sys.get_state(pid).game.pack.questions |> Enum.map(& &1.id)
  end

  describe "a listed room (PROTOCOL.md §3.5)" do
    defp listed_codes, do: Enum.map(Rooms.listed(), & &1.room_code)

    test "the host puts it on the list and takes it off again", %{code: code, socket: host} do
      refute code in listed_codes()

      ref = push(host, "host_set_listed", %{"listed" => true})
      assert_reply ref, :ok
      assert_push "state", %{listed: true}
      assert code in listed_codes()

      {:ok, _, _} = join_room(code, %{"display_name" => "Sam"})
      assert %{player_count: 1} = Enum.find(Rooms.listed(), &(&1.room_code == code))

      ref = push(host, "host_set_listed", %{"listed" => false})
      assert_reply ref, :ok
      refute code in listed_codes()
    end

    test "turns away a quiz from somebody's device, and takes a published one", %{socket: host} do
      ref = push(host, "host_set_listed", %{"listed" => true})
      assert_reply ref, :ok

      ref = select(host, [%{"quiz" => QuizFixtures.quiz_params()}])
      assert_reply ref, :error, %{code: "quiz_not_public"}

      ref = select(host, [%{"quiz_id" => stored!("Library", ["One?"]).id}])
      assert_reply ref, :ok
    end
  end
end

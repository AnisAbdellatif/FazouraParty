defmodule Fazoura.GameTest do
  use ExUnit.Case, async: true

  alias Fazoura.Game
  alias Fazoura.Game.{Pack, View}
  alias Fazoura.ProtocolFixtures

  @scoring ProtocolFixtures.load!("scoring.json")
  @t0 1_000_000

  defp pack(question_count \\ 2) do
    Pack.from_map(%{
      "title" => "Test",
      "questions" =>
        for i <- 1..question_count do
          %{
            "id" => "q#{i}",
            "prompt" => "Question #{i}?",
            "accepted_answers" => ["Right"],
            "time_limit_ms" => 10_000
          }
        end
    })
  end

  defp game_with_players(names, question_count \\ 2) do
    Enum.reduce(names, Game.new("ROOM42", pack(question_count)), fn name, game ->
      {:ok, game} = Game.add_player(game, name, name)
      game
    end)
  end

  defp ok!({:ok, game}), do: game

  # Ending a question leaves it open for the closing window (PROTOCOL.md §6); most tests
  # only care that it ended, so this lets the window run out. `close/2` stops short of it.
  defp host(game, intent, now \\ @t0)

  defp host(%Game{phase: :question} = game, :next, now) do
    with {:ok, closing} <- close(game, now),
         do: {:ok, Game.tick(closing, now + Game.closing_window_ms())}
  end

  defp host(game, intent, now), do: Game.handle(game, :host, intent, now)

  defp close(game, now \\ @t0), do: Game.handle(game, :host, :next, now)

  defp submit(game, id, answer, now \\ @t0),
    do: Game.handle(game, {:player, id}, {:submit, %{"answer" => answer}}, now)

  # One question of `difficulty`, with difficulty scoring on or off.
  defp graded_game(difficulty, bonus, score \\ 0) do
    pack =
      Pack.from_map(%{
        "title" => "T",
        "questions" => [
          %{
            "id" => "q1",
            "prompt" => "?",
            "difficulty" => difficulty,
            "accepted_answers" => ["Right"],
            "time_limit_ms" => 10_000
          }
        ]
      })

    {:ok, game} = Game.add_player(Game.new("ROOM42", pack), "sam", "Sam")
    game = put_in(game.players["sam"].score, score)
    game |> configure(1, 10_000, bonus) |> ok!() |> host(:next) |> ok!()
  end

  describe "difficulty scoring (fixtures)" do
    for c <- @scoring["points"] do
      test "#{c["difficulty"]}, difficulty scoring #{c["bonus"]} is worth #{inspect(c["points"])}" do
        c = unquote(Macro.escape(c))
        game = graded_game(c["difficulty"], c["bonus"])
        points = c["points"]

        assert View.room_state(game, :host, @t0).question.points == %{
                 right: points["right"],
                 wrong: points["wrong"],
                 skipped: points["skipped"]
               }
      end
    end

    for c <- @scoring["delta"] do
      test "#{c["difficulty"]}, bonus #{c["bonus"]}, correct=#{c["correct"]} -> #{c["delta"]}" do
        c = unquote(Macro.escape(c))
        answer = if c["correct"], do: "Right", else: "Wrong"

        game =
          graded_game(c["difficulty"], c["bonus"])
          |> submit("sam", answer)
          |> ok!()
          |> host(:next)
          |> ok!()

        assert game.players["sam"].score == c["delta"]
        assert [%{delta: delta, correct: correct}] = View.room_state(game, :host, @t0).submissions
        assert {delta, correct} == {c["delta"], c["correct"]}
      end
    end

    for %{"name" => name} = c <- @scoring["skipped"] do
      test "skipped: #{name}" do
        c = unquote(Macro.escape(c))

        game =
          graded_game(c["difficulty"], c["bonus"], c["score_before_question"])
          |> host(:next)
          |> ok!()

        assert game.players["sam"].score == c["score_after_scoring"]

        # A player who said nothing still gets a row, with no answer to show.
        view = View.room_state(game, {:player, "sam"}, @t0)
        assert [%{player_id: "sam", answer: nil, correct: false, delta: delta}] = view.submissions
        assert delta == c["delta"]
        assert view.you.submission == %{answer: nil, correct: false, delta: c["delta"]}
      end
    end

    for %{"name" => name} = c <- @scoring["override"] do
      test "override: #{name}" do
        c = unquote(Macro.escape(c))
        answer = if c["auto_correct"], do: "Right", else: "Wrong"

        game =
          graded_game(c["difficulty"], c["bonus"], c["score_before_question"])
          |> submit("sam", answer)
          |> ok!()
          |> host(:next)
          |> ok!()

        assert game.players["sam"].score == c["score_after_scoring"]

        payload = %{"player_id" => "sam", "correct" => c["override"]}
        game = game |> host({:override, payload}) |> ok!()
        assert game.players["sam"].score == c["score_after_override"]
      end
    end

    test "a player who joined mid-question is not charged for it" do
      game = graded_game("easy", true)
      {:ok, game} = Game.add_player(game, "late", "Late")
      game = game |> host(:next) |> ok!()

      assert game.players["sam"].score == -10
      assert game.players["late"].score == 0

      # ...and has no row at all, rather than an empty one.
      assert [%{player_id: "sam"}] = View.room_state(game, :host, @t0).submissions
      assert View.room_state(game, {:player, "late"}, @t0).you.submission == nil
    end

    test "not answering cannot be overridden" do
      game = graded_game("easy", true) |> host(:next) |> ok!()

      assert host(game, {:override, %{"player_id" => "sam", "correct" => true}}) ==
               {:error, :no_submission}
    end
  end

  describe "players" do
    test "names are trimmed, 1-20 chars and unique case-insensitively" do
      game = Game.new("ROOM42", pack())
      assert {:ok, game} = Game.add_player(game, "p1", "  Sam ")
      assert game.players["p1"].name == "Sam"
      assert Game.add_player(game, "p2", "sAM") == {:error, :name_taken}
      assert Game.add_player(game, "p2", "   ") == {:error, :invalid_name}
      assert Game.add_player(game, "p2", String.duplicate("a", 21)) == {:error, :invalid_name}
      assert Game.add_player(game, "p2", nil) == {:error, :invalid_name}
    end

    test "room is capped at max_players" do
      game = game_with_players(Enum.map(1..Game.max_players(), &"player#{&1}"))
      assert Game.add_player(game, "extra", "Extra") == {:error, :room_full}
    end
  end

  describe "room size (§6.5)" do
    test "the host makes the room smaller, never below who is already in it" do
      game = game_with_players(["Sam", "Kim"])
      assert {game.room_size, game.room_size_limit} == {Game.max_players(), Game.max_players()}

      game = ok!(host(game, {:set_room_size, %{"room_size" => 2}}))
      assert game.room_size == 2
      assert Game.add_player(game, "p3", "Lee") == {:error, :room_full}

      assert host(game, {:set_room_size, %{"room_size" => 1}}) == {:error, :invalid_room_size}

      assert host(game, {:set_room_size, %{"room_size" => Game.max_players() + 1}}) ==
               {:error, :invalid_room_size}

      assert host(game, {:set_room_size, %{"room_size" => "3"}}) == {:error, :invalid_payload}

      assert Game.handle(game, {:player, "Sam"}, {:set_room_size, %{"room_size" => 3}}, @t0) ==
               {:error, :not_host}
    end

    test "it can change mid-game, and a rematch or a new quiz leaves it alone" do
      game = game_with_players(["Sam"]) |> host(:next) |> ok!()
      game = ok!(host(game, {:set_room_size, %{"room_size" => 5}}))
      game = ok!(Game.select_quiz(%{game | phase: :lobby}, pack(3)))
      assert game.room_size == 5
    end

    test "a code raises the limit and grows the room to it, and never lowers it" do
      game = game_with_players(["Sam"])
      game = ok!(host(game, {:set_room_size, %{"room_size" => 4}}))

      game = ok!(host(game, {:unlock_room_size, 60}))
      assert {game.room_size, game.room_size_limit} == {60, 60}

      game = ok!(host(game, {:unlock_room_size, 40}))
      assert game.room_size_limit == 60
      assert ok!(host(game, {:set_room_size, %{"room_size" => 50}})).room_size == 50
    end

    test "a LAN room has no codes to redeem" do
      game = Game.new("LAN001", pack(), mode: :lan)
      assert host(game, {:unlock_room_size, 60}) == {:error, :cloud_only}
      assert Game.check_unlock(game, :host) == {:error, :cloud_only}
    end

    test "only whoever holds the host role may unlock" do
      game = game_with_players(["Sam", "Kim"])
      assert Game.check_unlock(game, :host) == :ok
      assert Game.check_unlock(game, {:player, "Sam"}) == {:error, :not_host}

      game = %{game | host_player_id: "Sam"}
      assert Game.check_unlock(game, {:player, "Sam"}) == :ok
    end
  end

  describe "phases" do
    test "full cycle over two questions" do
      game = game_with_players(["sam"])
      assert game.phase == :lobby

      game = game |> host(:next) |> ok!()
      assert {game.phase, game.question_index, game.deadline} == {:question, 0, @t0 + 10_000}

      game = game |> host(:next) |> ok!()
      assert game.phase == :scoring
      game = game |> host(:next) |> ok!()
      assert game.phase == :leaderboard
      game = game |> host(:next) |> ok!()
      assert {game.phase, game.question_index} == {:question, 1}
      game = game |> host(:next) |> ok!() |> host(:next) |> ok!() |> host(:next) |> ok!()
      assert game.phase == :finished
      assert host(game, :next) == {:error, :invalid_phase}
    end

    test "tick scores the question once the deadline passes" do
      # Kim never answers, so the question runs its clock rather than ending the
      # moment Sam is done.
      game =
        game_with_players(["sam", "kim"])
        |> host(:next)
        |> ok!()
        |> submit("sam", "right")
        |> ok!()

      assert Game.tick(game, @t0 + 9_999).phase == :question
      scored = Game.tick(game, @t0 + 10_000)
      assert scored.phase == :scoring
      assert scored.players["sam"].score == 10
      assert scored.players["kim"].score == -10
    end

    test "the question ends the moment the last player answers" do
      game = game_with_players(["sam", "kim"]) |> host(:next) |> ok!()

      one = game |> submit("sam", "right") |> ok!()
      assert one.phase == :question, "still waiting on kim"

      both = one |> submit("kim", "right", @t0 + 1) |> ok!()
      assert both.phase == :scoring
      assert both.deadline == nil
      assert both.players["sam"].score == 10
    end

    test "a room nobody answered in runs its clock down" do
      # Everyone gone and nothing submitted: the pack must not race past
      # unattended, so only the deadline ends this.
      game =
        game_with_players(["sam"])
        |> host(:next)
        |> ok!()
        |> Game.set_connected("sam", false, @t0)

      assert Game.tick(game, @t0 + 9_999).phase == :question
      assert Game.tick(game, @t0 + 10_000).phase == :scoring
    end

    test "a dropped player is waited out for the grace, then stops holding the room" do
      game =
        game_with_players(["sam", "kim"])
        |> host(:next)
        |> ok!()
        |> Game.set_connected("kim", false, @t0)
        |> submit("sam", "right", @t0 + 1)
        |> ok!()

      assert game.phase == :question, "kim may still be coming back"
      assert Game.tick(game, @t0 + 4_999).phase == :question

      # The grace runs from the disconnect, not from the last submission.
      scored = Game.tick(game, @t0 + 5_000)
      assert scored.phase == :scoring
      assert scored.players["kim"].score == -10
    end

    test "a player who reconnects inside the grace still gets the question" do
      game =
        game_with_players(["sam", "kim"])
        |> host(:next)
        |> ok!()
        |> Game.set_connected("kim", false, @t0)
        |> submit("sam", "right", @t0 + 1)
        |> ok!()
        |> Game.set_connected("kim", true, @t0 + 4_000)

      assert Game.tick(game, @t0 + 9_000).phase == :question
      assert game |> submit("kim", "right", @t0 + 9_000) |> ok!() |> then(& &1.phase) == :scoring
    end

    test "the grace is not renewed by flapping" do
      game =
        game_with_players(["sam", "kim"])
        |> host(:next)
        |> ok!()
        |> Game.set_connected("kim", false, @t0)
        |> Game.set_connected("kim", false, @t0 + 4_000)
        |> submit("sam", "right", @t0 + 1)
        |> ok!()

      assert Game.tick(game, @t0 + 5_000).phase == :scoring
    end

    test "a paused question never ends itself" do
      game =
        game_with_players(["sam", "kim"])
        |> host(:next)
        |> ok!()
        |> Game.set_connected("kim", false, @t0)
        |> submit("sam", "right", @t0 + 1)
        |> ok!()
        |> host(:pause, @t0 + 2)
        |> ok!()

      assert Game.tick(game, @t0 + 60_000).phase == :question
      assert Game.deadline(game) == nil
    end

    test "the timer wakes for a grace that expires before the deadline" do
      game =
        game_with_players(["sam", "kim"])
        |> host(:next)
        |> ok!()
        |> Game.set_connected("kim", false, @t0)
        |> submit("sam", "right", @t0 + 1)
        |> ok!()

      assert Game.deadline(game) == @t0 + 5_000, "the grace, not the far-off deadline"
    end

    test "ending a question gives what is still being typed the closing window to arrive" do
      game = game_with_players(["sam", "kim"]) |> host(:next) |> ok!()

      closing = game |> close(@t0 + 1_000) |> ok!()
      assert closing.phase == :question
      assert closing.deadline == @t0 + 1_000 + Game.closing_window_ms()

      # Sam's typed answer is sent for them just before the new deadline, and counts.
      late = closing |> submit("sam", "Right", closing.deadline - 700) |> ok!()
      assert late.phase == :question, "still waiting on kim"

      scored = Game.tick(late, closing.deadline)
      assert scored.phase == :scoring
      assert {scored.players["sam"].score, scored.players["kim"].score} == {10, -10}
    end

    test "the closing window still ends the moment nobody is left to wait for" do
      closing = game_with_players(["sam"]) |> host(:next) |> ok!() |> close() |> ok!()
      assert closing |> submit("sam", "Right", @t0 + 500) |> ok!() |> then(& &1.phase) == :scoring
    end

    test "ending a closing question again does not cut the window short" do
      closing = game_with_players(["sam"]) |> host(:next) |> ok!() |> close() |> ok!()
      again = closing |> close(@t0 + 1_500) |> ok!()
      assert again.deadline == closing.deadline
    end

    test "ending a question with less time left than the window keeps the deadline" do
      game = game_with_players(["sam"]) |> host(:next) |> ok!()
      assert game |> close(@t0 + 9_000) |> ok!() |> then(& &1.deadline) == @t0 + 10_000
    end

    test "ending a paused question resumes it into the closing window" do
      paused = game_with_players(["sam"]) |> host(:next) |> ok!() |> host(:pause) |> ok!()

      closing = paused |> close(@t0 + 60_000) |> ok!()

      assert {closing.deadline, closing.paused_remaining_ms} ==
               {@t0 + 60_000 + Game.closing_window_ms(), nil}

      assert closing |> submit("sam", "Right", @t0 + 60_500) |> ok!() |> then(& &1.phase) ==
               :scoring
    end

    test "ending a question nobody can still answer scores it at once" do
      game =
        game_with_players(["kim"])
        |> host(:next)
        |> ok!()
        |> Game.set_connected("kim", false, @t0)

      assert game |> close(@t0 + 1_000) |> ok!() |> then(& &1.phase) == :question,
             "kim is inside the grace and may be back"

      assert game |> close(@t0 + 5_000) |> ok!() |> then(& &1.phase) == :scoring
    end

    test "pause freezes the timer and resume restores the remaining time" do
      game = game_with_players(["sam"]) |> host(:next) |> ok!()

      paused = game |> host(:pause, @t0 + 4_000) |> ok!()
      assert {paused.deadline, paused.paused_remaining_ms} == {nil, 6_000}
      assert host(paused, :pause) == {:error, :paused}
      assert Game.tick(paused, @t0 + 999_999).phase == :question
      assert submit(paused, "sam", "Right") == {:error, :paused}

      resumed = paused |> host(:resume, @t0 + 50_000) |> ok!()
      assert {resumed.deadline, resumed.paused_remaining_ms} == {@t0 + 56_000, nil}
      assert host(resumed, :resume) == {:error, :not_paused}
    end
  end

  describe "intent validation" do
    setup do
      %{game: game_with_players(["sam", "alex"]) |> host(:next) |> ok!()}
    end

    test "role checks", %{game: game} do
      assert Game.handle(game, {:player, "sam"}, :next, @t0) == {:error, :not_host}
      assert Game.handle(game, {:player, "sam"}, {:override, %{}}, @t0) == {:error, :not_host}
      assert Game.handle(game, :host, {:submit, %{}}, @t0) == {:error, :not_player}
    end

    test "one submission per player, before the deadline", %{game: game} do
      game = game |> submit("sam", "Right") |> ok!()
      assert submit(game, "sam", "Right") == {:error, :already_submitted}
      assert submit(game, "alex", "Right", @t0 + 10_000) == {:error, :invalid_phase}
    end

    test "answer must be 1-100 chars", %{game: game} do
      assert submit(game, "sam", "  ") == {:error, :invalid_answer}
      assert submit(game, "sam", String.duplicate("a", 101)) == {:error, :invalid_answer}
      assert submit(game, "sam", 42) == {:error, :invalid_answer}
    end

    test "override errors", %{game: game} do
      game = game |> submit("sam", "Right") |> ok!()

      assert host(game, {:override, %{"player_id" => "sam", "correct" => false}}) ==
               {:error, :invalid_phase}

      game = game |> host(:next) |> ok!()

      assert host(game, {:override, %{"player_id" => "nobody", "correct" => true}}) ==
               {:error, :unknown_player}

      assert host(game, {:override, %{"player_id" => "alex", "correct" => true}}) ==
               {:error, :no_submission}

      assert host(game, {:override, %{"player_id" => "sam"}}) == {:error, :invalid_payload}
    end
  end

  defp configure(game, count, time, bonus \\ false),
    do:
      host(
        game,
        {:configure,
         %{"question_count" => count, "time_limit_ms" => time, "difficulty_multiplier" => bonus}}
      )

  defp configure(game, count, time, bonus, difficulties),
    do:
      host(
        game,
        {:configure,
         %{
           "question_count" => count,
           "time_limit_ms" => time,
           "difficulty_multiplier" => bonus,
           "difficulties" => difficulties
         }}
      )

  # Two easy questions and one hard one, so selecting a difficulty really does
  # change the size of the pool.
  defp mixed_game do
    pack =
      Pack.from_map(%{
        "title" => "Mixed",
        "questions" =>
          for {difficulty, i} <- Enum.with_index(["easy", "easy", "hard"], 1) do
            %{
              "id" => "q#{i}",
              "prompt" => "Question #{i}?",
              "difficulty" => difficulty,
              "accepted_answers" => ["Right"],
              "time_limit_ms" => 10_000
            }
          end
      })

    Game.new("ROOM42", pack, shuffle_questions?: false)
  end

  describe "settings" do
    test "defaults to the whole pack at the first question's time limit" do
      game = game_with_players(["sam"], 3)

      assert game.settings == %{
               question_count: 3,
               time_limit_ms: 10_000,
               difficulty_multiplier: false,
               difficulties: ["easy"],
               available_difficulties: ["easy"]
             }

      view = View.room_state(game, :host, @t0)
      assert view.question_count == 3

      assert view.settings == %{
               question_count: 3,
               time_limit_ms: 10_000,
               difficulty_multiplier: false,
               difficulties: ["easy"],
               available_difficulties: ["easy"],
               max_question_count: 3,
               min_time_limit_ms: 10_000,
               max_time_limit_ms: 120_000
             }
    end

    test "host sets question count and time limit in the lobby only" do
      game = game_with_players(["sam"], 3)

      for {count, time} <- [{0, 20_000}, {4, 20_000}, {2, 9_999}, {2, 120_001}, {"2", 20_000}] do
        assert configure(game, count, time) == {:error, :invalid_settings}
      end

      assert host(game, {:configure, %{}}) == {:error, :invalid_settings}

      assert host(game, {:configure, %{"question_count" => 2, "time_limit_ms" => 20_000}}) ==
               {:error, :invalid_settings}

      assert configure(game, 2, 20_000, "yes") == {:error, :invalid_settings}

      assert Game.handle(game, {:player, "sam"}, {:configure, %{}}, @t0) ==
               {:error, :not_host}

      game = game |> configure(2, 15_000) |> ok!()
      game = game |> host(:next) |> ok!()
      assert game.deadline == @t0 + 15_000
      assert View.room_state(game, :host, @t0).question.time_limit_ms == 15_000
      assert configure(game, 1, 15_000) == {:error, :invalid_phase}

      # Two questions, then finished.
      game =
        Enum.reduce(1..6, game, fn _, g -> g |> host(:next) |> ok!() end)

      assert game.phase == :finished
    end
  end

  describe "question count and difficulty bonus" do
    test "the round can use the full pack size" do
      game = game_with_players(["sam"], 25)
      assert game.settings.question_count == 25
      assert View.room_state(game, :host, @t0).settings.max_question_count == 25
      assert configure(game, 26, 30_000) == {:error, :invalid_settings}
      assert {:ok, _} = configure(game, 25, 30_000)
    end

    test "only difficulties the pack has can be selected" do
      game = mixed_game()

      for selected <- [["easy", "medium"], [], ["brutal"]] do
        assert configure(game, 1, 15_000, false, selected) == {:error, :invalid_settings}
      end
    end

    test "narrowing the difficulties clamps the count instead of failing" do
      game = mixed_game()
      assert game.settings.available_difficulties == ["easy", "hard"]
      assert View.room_state(game, :host, @t0).settings.max_question_count == 3

      # Three questions were on offer; only the one hard question now is, so
      # the count follows the selection down rather than being refused.
      game = game |> configure(3, 10_000, false, ["hard"]) |> ok!()
      assert game.settings.question_count == 1
      assert View.room_state(game, :host, @t0).settings.max_question_count == 1

      # Asking for more than the *current* selection holds is a mistake.
      assert configure(game, 2, 10_000, false, ["hard"]) == {:error, :invalid_settings}

      # The round is played from the filtered order, not the whole pack.
      game = game |> host(:next) |> ok!()
      question = View.room_state(game, :host, @t0).question
      assert {question.id, question.difficulty} == {"q3", "hard"}
    end

    test "unknown difficulties are rejected when loading a pack" do
      assert_raise ArgumentError, fn ->
        Pack.from_map(%{
          "title" => "T",
          "questions" => [
            %{"id" => "q", "prompt" => "?", "difficulty" => "brutal", "accepted_answers" => []}
          ]
        })
      end
    end
  end

  describe "avatar hues" do
    test "stay within 0..359 and spread away from hues already in the room" do
      {:ok, game} = Game.add_player(Game.new("ROOM42", pack()), "a", "A", 100)
      candidates = Stream.cycle([95, 110, 280, 102]) |> Stream.take(12) |> Enum.to_list()
      {:ok, agent} = Agent.start_link(fn -> candidates end)
      next = fn -> Agent.get_and_update(agent, fn [h | t] -> {h, t} end) end

      assert Game.pick_avatar_hue(game, next) == 280

      for _ <- 1..50, do: assert(Game.pick_avatar_hue(game) in 0..359)
      assert View.room_state(game, :host, @t0).players |> hd() |> Map.fetch!(:avatar_hue) == 100
    end
  end

  describe "rematch" do
    test "resets scores and returns to quiz selection in the same room" do
      game = game_with_players(["sam", "alex"], 3)

      game = game |> configure(2, 10_000) |> ok!()

      game = game |> host(:next) |> ok!() |> submit("sam", "Right") |> ok!()
      game = Enum.reduce(1..6, game, fn _, g -> g |> host(:next) |> ok!() end)
      assert game.phase == :finished
      # One right (+10) and one let go by (-10) for Sam; alex answered neither.
      assert game.players["sam"].score == 0
      assert game.players["alex"].score == -20

      assert Game.handle(game, {:player, "sam"}, :rematch, @t0) == {:error, :not_host}

      game = game |> host(:rematch) |> ok!()
      assert {game.phase, game.game_number, game.question_index} == {:lobby, 2, nil}
      assert Enum.map(game.players, fn {_, p} -> p.score end) == [0, 0]
      assert map_size(game.players) == 2
      assert game.settings.question_count == 0
      assert game.pack.questions == []
      assert host(game, :rematch) == {:error, :invalid_phase}

      {:ok, game} = Game.select_quiz(game, pack(3))
      game = game |> host(:next) |> ok!()
      assert View.room_state(game, :host, @t0).question.id in ["q1", "q2", "q3"]
      assert View.room_state(game, :host, @t0).game_number == 2
    end
  end

  describe "listed rooms" do
    # What `Quizzes.to_pack/1` gives a stored quiz: every question knows where it came from.
    defp published(pack), do: %{pack | questions: Enum.map(pack.questions, &%{&1 | quiz_id: "q"})}

    defp lobby(opts),
      do: Game.new("ROOM42", %Pack{titles: [], questions: []}, opts)

    test "plays published quizzes only" do
      game = lobby(listed: true)

      assert Game.handle(game, :host, {:select_quiz, pack()}, @t0) == {:error, :quiz_not_public}

      assert {:ok, %Game{listed: true}} =
               Game.handle(game, :host, {:select_quiz, published(pack())}, @t0)
    end

    test "a room joined by code plays anything" do
      assert {:ok, _game} = lobby([]) |> Game.handle(:host, {:select_quiz, pack()}, @t0)
    end

    test "the host lists and unlists in the lobby, and the snapshot says which" do
      game = lobby([]) |> host({:set_listed, %{"listed" => true}}) |> ok!()
      assert View.room_state(game, :host, @t0).listed == true

      game = game |> host({:set_listed, %{"listed" => false}}) |> ok!()
      assert View.room_state(game, :host, @t0).listed == false
    end

    test "a quiz from somebody's device keeps the room off the list until it is swapped" do
      game = lobby([]) |> host({:select_quiz, pack()}) |> ok!()
      assert host(game, {:set_listed, %{"listed" => true}}) == {:error, :quiz_not_public}

      game = game |> host({:select_quiz, published(pack())}) |> ok!()
      assert {:ok, %Game{listed: true}} = host(game, {:set_listed, %{"listed" => true}})
    end

    test "only in the lobby, only with a boolean, and never on a LAN host" do
      assert host(lobby([]), {:set_listed, %{"listed" => "yes"}}) == {:error, :invalid_payload}
      assert host(lobby([]), {:set_listed, %{}}) == {:error, :invalid_payload}

      playing = game_with_players(["sam"]) |> host(:next) |> ok!()
      assert host(playing, {:set_listed, %{"listed" => true}}) == {:error, :invalid_phase}

      lan = lobby(mode: :lan)
      assert host(lan, {:set_listed, %{"listed" => true}}) == {:error, :cloud_only}
      assert lobby(mode: :lan, listed: true).listed == false
    end

    test "players cannot list the room" do
      {:ok, game} = Game.add_player(lobby([]), "sam", "Sam")

      assert Game.handle(game, {:player, "sam"}, {:set_listed, %{"listed" => true}}, @t0) ==
               {:error, :not_host}
    end
  end

  describe "removing a player" do
    test "they are gone, with no penalty, and the question stops waiting for them" do
      game = game_with_players(["sam", "kim"]) |> host(:next) |> ok!()
      game = game |> submit("sam", "Right") |> ok!()
      assert game.phase == :question, "still waiting on kim"

      removed = game |> host({:remove_player, %{"player_id" => "kim"}}) |> ok!()

      refute Game.player?(removed, "kim")
      assert removed.phase == :scoring, "nobody is left to wait for"
      assert removed.players["sam"].score == 10
    end

    test "not the host's own seat, not somebody who is not here, and only by the host" do
      {:ok, game} = Game.add_host_player(game_with_players(["sam"]), "hana", "Hana")

      assert host(game, {:remove_player, %{"player_id" => "hana"}}) == {:error, :invalid_payload}
      assert host(game, {:remove_player, %{"player_id" => "nope"}}) == {:error, :unknown_player}
      assert host(game, {:remove_player, %{}}) == {:error, :invalid_payload}

      assert Game.handle(game, {:player, "sam"}, {:remove_player, %{"player_id" => "hana"}}, @t0) ==
               {:error, :not_host}
    end
  end

  describe "names and answers in a public room" do
    defp public(names) do
      Enum.reduce(names, Game.new("ROOM42", pack(), listed: true), fn name, game ->
        {:ok, game} = Game.add_player(game, name, name)
        game
      end)
    end

    test "a public room turns a blocked name away; a room joined by code does not" do
      assert Game.add_player(public([]), "p", "Fuck Off") == {:error, :name_not_allowed}
      assert {:ok, _} = Game.add_player(game_with_players([]), "p", "Fuck Off")
    end

    test "a room with a blocked name in it cannot go public" do
      lobby = Game.new("ROOM42", %Pack{titles: [], questions: []})
      {:ok, game} = Game.add_player(lobby, "p", "zebi")

      assert host(game, {:set_listed, %{"listed" => true}}) == {:error, :name_not_allowed}
    end

    test "a wrong answer with a blocked word reaches everyone but its author as ***" do
      game =
        public(["sam", "kim", "ali"])
        |> host(:next)
        |> ok!()
        |> submit("sam", "fuck this")
        |> ok!()
        |> submit("kim", "Right")
        |> ok!()
        |> submit("ali", "wrong")
        |> ok!()

      answers = fn recipient ->
        View.room_state(game, recipient, @t0).submissions
        |> Map.new(&{&1.player_id, &1.answer})
      end

      assert answers.({:player, "kim"}) == %{"sam" => "***", "kim" => "Right", "ali" => "wrong"}
      assert answers.(:host)["sam"] == "***"
      assert answers.({:player, "sam"})["sam"] == "fuck this"
    end
  end

  describe "views" do
    test "players never see answers or others' submissions before scoring" do
      game =
        game_with_players(["sam", "alex"])
        |> host(:next)
        |> ok!()
        |> submit("sam", "Right")
        |> ok!()

      player = View.room_state(game, {:player, "alex"}, @t0)
      assert player.accepted_answers == nil
      assert player.submissions == nil
      assert player.you.submission == nil
      assert Enum.find(player.players, &(&1.id == "sam")).has_submitted

      own = View.room_state(game, {:player, "sam"}, @t0)
      assert own.you.submission == %{answer: "Right", correct: nil, delta: nil}

      host_view = View.room_state(game, :host, @t0)
      assert host_view.accepted_answers == nil
      assert host_view.submissions == nil
      assert host_view.you == %{role: "host", player_id: nil, host_token: nil, submission: nil}

      scored = game |> host(:next) |> ok!() |> View.room_state({:player, "alex"}, @t0)
      assert scored.accepted_answers == ["Right"]

      assert [
               %{player_id: "sam", correct: true, delta: 10},
               %{player_id: "alex", answer: nil, correct: false, delta: -10}
             ] = scored.submissions
    end

    test "a playing host submits, sees nothing early, and can override their own answer" do
      {:ok, game} = Game.add_host_player(game_with_players(["sam"]), "hana", "Hana")
      assert {:ok, ^game} = Game.add_host_player(game, "other", "Other")
      assert Game.add_player(game, "x", "HANA") == {:error, :name_taken}

      game = game |> host(:next) |> ok!()
      game = game |> host({:submit, %{"answer" => "Rigth"}}) |> ok!()

      assert host(game, {:submit, %{"answer" => "Right"}}) ==
               {:error, :already_submitted}

      during = View.room_state(game, :host, @t0)
      assert {during.accepted_answers, during.submissions} == {nil, nil}

      assert during.you == %{
               role: "host",
               player_id: "hana",
               host_token: nil,
               submission: %{answer: "Rigth", correct: nil, delta: nil}
             }

      assert [%{id: "hana", is_host: true, has_submitted: true}, %{id: "sam", is_host: false}] =
               during.players

      game = game |> host(:next) |> ok!()
      assert game.players["hana"].score == -10
      assert View.room_state(game, :host, @t0).accepted_answers == ["Right"]

      game = game |> host({:override, %{"player_id" => "hana", "correct" => true}}) |> ok!()
      assert game.players["hana"].score == 10

      # Sam let the question go by, and is told what that cost rather than nothing.
      assert View.room_state(game, {:player, "sam"}, @t0).you.submission ==
               %{answer: nil, correct: false, delta: -10}
    end

    test "players are sorted by score desc, then name case-insensitively" do
      game = game_with_players(["bob", "Alice", "carl"])
      game = put_in(game.players["carl"].score, 5)

      names = View.room_state(game, :host, @t0).players |> Enum.map(& &1.name)
      assert names == ["carl", "Alice", "bob"]
    end

    test "finished hides question data from everyone" do
      game = game_with_players(["sam"], 1)
      game = Enum.reduce(1..4, game, fn _, g -> g |> host(:next) |> ok!() end)
      assert game.phase == :finished

      view = View.room_state(game, :host, @t0)
      assert {view.question, view.accepted_answers, view.submissions} == {nil, nil, nil}
    end
  end
end

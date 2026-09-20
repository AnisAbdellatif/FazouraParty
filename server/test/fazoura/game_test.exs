defmodule Fazoura.GameTest do
  use ExUnit.Case, async: true

  alias Fazoura.Game
  alias Fazoura.Game.Pack
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

  defp host(game, intent, now \\ @t0), do: Game.handle(game, :host, intent, now)

  defp submit(game, id, answer, wager, now \\ @t0),
    do: Game.handle(game, {:player, id}, {:submit, %{"answer" => answer, "wager" => wager}}, now)

  describe "wager scoring (fixtures)" do
    for %{"wager" => wager, "correct" => correct, "delta" => delta} <- @scoring["delta"] do
      test "wager #{wager}, correct=#{correct} -> #{delta}" do
        submission = %{
          answer: "x",
          wager: unquote(wager),
          auto_correct: unquote(correct),
          override: nil
        }

        assert Game.delta(submission) == unquote(delta)
      end
    end

    for %{"name" => name} = c <- @scoring["override"] do
      test "override: #{name}" do
        c = unquote(Macro.escape(c))
        answer = if c["auto_correct"], do: "Right", else: "Wrong"

        game = game_with_players(["sam"])
        game = put_in(game.players["sam"].score, c["score_before_question"])
        game = game |> host(:next) |> ok!() |> submit("sam", answer, c["wager"]) |> ok!()
        game = game |> host(:next) |> ok!()
        assert game.players["sam"].score == c["score_after_scoring"]

        payload = %{"player_id" => "sam", "correct" => c["override"]}
        game = game |> host({:override, payload}) |> ok!()
        assert game.players["sam"].score == c["score_after_override"]
      end
    end

    for wager <- @scoring["invalid_wagers"] do
      test "rejects wager #{inspect(wager)}" do
        game = game_with_players(["sam"]) |> host(:next) |> ok!()

        assert submit(game, "sam", "Right", unquote(Macro.escape(wager))) ==
                 {:error, :invalid_wager}
      end
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

    test "room is capped at 100 players" do
      game = game_with_players(Enum.map(1..100, &"player#{&1}"))
      assert Game.add_player(game, "extra", "Extra") == {:error, :room_full}
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
      game =
        game_with_players(["sam"]) |> host(:next) |> ok!() |> submit("sam", "right", 3) |> ok!()

      assert Game.tick(game, @t0 + 9_999).phase == :question
      scored = Game.tick(game, @t0 + 10_000)
      assert scored.phase == :scoring
      assert scored.players["sam"].score == 3
    end

    test "pause freezes the timer and resume restores the remaining time" do
      game = game_with_players(["sam"]) |> host(:next) |> ok!()

      paused = game |> host(:pause, @t0 + 4_000) |> ok!()
      assert {paused.deadline, paused.paused_remaining_ms} == {nil, 6_000}
      assert host(paused, :pause) == {:error, :paused}
      assert Game.tick(paused, @t0 + 999_999).phase == :question
      assert submit(paused, "sam", "Right", 5) == {:error, :paused}

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
      game = game |> submit("sam", "Right", 5) |> ok!()
      assert submit(game, "sam", "Right", 5) == {:error, :already_submitted}
      assert submit(game, "alex", "Right", 5, @t0 + 10_000) == {:error, :invalid_phase}
    end

    test "answer must be 1-100 chars", %{game: game} do
      assert submit(game, "sam", "  ", 5) == {:error, :invalid_answer}
      assert submit(game, "sam", String.duplicate("a", 101), 5) == {:error, :invalid_answer}
      assert submit(game, "sam", 42, 5) == {:error, :invalid_answer}
    end

    test "override errors", %{game: game} do
      game = game |> submit("sam", "Right", 5) |> ok!()

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

      view = Game.view(game, :host, @t0)
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
      assert Game.view(game, :host, @t0).question.time_limit_ms == 15_000
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
      assert Game.view(game, :host, @t0).settings.max_question_count == 25
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
      assert Game.view(game, :host, @t0).settings.max_question_count == 3

      # Three questions were on offer; only the one hard question now is, so
      # the count follows the selection down rather than being refused.
      game = game |> configure(3, 10_000, false, ["hard"]) |> ok!()
      assert game.settings.question_count == 1
      assert Game.view(game, :host, @t0).settings.max_question_count == 1

      # Asking for more than the *current* selection holds is a mistake.
      assert configure(game, 2, 10_000, false, ["hard"]) == {:error, :invalid_settings}

      # The round is played from the filtered order, not the whole pack.
      game = game |> host(:next) |> ok!()
      question = Game.view(game, :host, @t0).question
      assert {question.id, question.difficulty} == {"q3", "hard"}
    end

    for c <- ProtocolFixtures.load!("scoring.json")["multiplier"] do
      test "#{c["difficulty"]}, bonus #{c["bonus"]}: wager #{c["wager"]} -> #{c["delta"]}" do
        c = unquote(Macro.escape(c))

        pack =
          Pack.from_map(%{
            "title" => "T",
            "questions" => [
              %{
                "id" => "q1",
                "prompt" => "?",
                "difficulty" => c["difficulty"],
                "accepted_answers" => ["Right"],
                "time_limit_ms" => 10_000
              }
            ]
          })

        {:ok, game} = Game.add_player(Game.new("ROOM42", pack), "sam", "Sam")
        game = game |> configure(1, 10_000, c["bonus"]) |> ok!() |> host(:next) |> ok!()
        assert Game.view(game, :host, @t0).question.multiplier == c["multiplier"]
        answer = if c["correct"], do: "Right", else: "Wrong"
        game = game |> submit("sam", answer, c["wager"]) |> ok!() |> host(:next) |> ok!()

        assert game.players["sam"].score == c["delta"]
        assert [%{multiplier: m, delta: d}] = Game.view(game, :host, @t0).submissions
        assert {m, d} == {c["multiplier"], c["delta"]}
      end
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
      assert Game.view(game, :host, @t0).players |> hd() |> Map.fetch!(:avatar_hue) == 100
    end
  end

  describe "rematch" do
    test "resets scores and returns to quiz selection in the same room" do
      game = game_with_players(["sam", "alex"], 3)

      game = game |> configure(2, 10_000) |> ok!()

      game = game |> host(:next) |> ok!() |> submit("sam", "Right", 7) |> ok!()
      game = Enum.reduce(1..6, game, fn _, g -> g |> host(:next) |> ok!() end)
      assert game.phase == :finished
      assert game.players["sam"].score == 7

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
      assert Game.view(game, :host, @t0).question.id in ["q1", "q2", "q3"]
      assert Game.view(game, :host, @t0).game_number == 2
    end
  end

  describe "views" do
    test "players never see answers or others' submissions before scoring" do
      game =
        game_with_players(["sam", "alex"])
        |> host(:next)
        |> ok!()
        |> submit("sam", "Right", 4)
        |> ok!()

      player = Game.view(game, {:player, "alex"}, @t0)
      assert player.accepted_answers == nil
      assert player.submissions == nil
      assert player.you.submission == nil
      assert Enum.find(player.players, &(&1.id == "sam")).has_submitted

      own = Game.view(game, {:player, "sam"}, @t0)
      assert own.you.submission == %{answer: "Right", wager: 4, correct: nil, delta: nil}

      host_view = Game.view(game, :host, @t0)
      assert host_view.accepted_answers == nil
      assert host_view.submissions == nil
      assert host_view.you == %{role: "host", player_id: nil, host_token: nil, submission: nil}

      scored = game |> host(:next) |> ok!() |> Game.view({:player, "alex"}, @t0)
      assert scored.accepted_answers == ["Right"]
      assert [%{player_id: "sam", correct: true, delta: 4}] = scored.submissions
    end

    test "a playing host submits, sees nothing early, and can override their own answer" do
      {:ok, game} = Game.add_host_player(game_with_players(["sam"]), "hana", "Hana")
      assert {:ok, ^game} = Game.add_host_player(game, "other", "Other")
      assert Game.add_player(game, "x", "HANA") == {:error, :name_taken}

      game = game |> host(:next) |> ok!()
      game = game |> host({:submit, %{"answer" => "Rigth", "wager" => 6}}) |> ok!()

      assert host(game, {:submit, %{"answer" => "Right", "wager" => 6}}) ==
               {:error, :already_submitted}

      during = Game.view(game, :host, @t0)
      assert {during.accepted_answers, during.submissions} == {nil, nil}

      assert during.you == %{
               role: "host",
               player_id: "hana",
               host_token: nil,
               submission: %{answer: "Rigth", wager: 6, correct: nil, delta: nil}
             }

      assert [%{id: "hana", is_host: true, has_submitted: true}, %{id: "sam", is_host: false}] =
               during.players

      game = game |> host(:next) |> ok!()
      assert game.players["hana"].score == -6
      assert Game.view(game, :host, @t0).accepted_answers == ["Right"]

      game = game |> host({:override, %{"player_id" => "hana", "correct" => true}}) |> ok!()
      assert game.players["hana"].score == 6
      assert Game.view(game, {:player, "sam"}, @t0).you.submission == nil
    end

    test "players are sorted by score desc, then name case-insensitively" do
      game = game_with_players(["bob", "Alice", "carl"])
      game = put_in(game.players["carl"].score, 5)

      names = Game.view(game, :host, @t0).players |> Enum.map(& &1.name)
      assert names == ["carl", "Alice", "bob"]
    end

    test "finished hides question data from everyone" do
      game = game_with_players(["sam"], 1)
      game = Enum.reduce(1..4, game, fn _, g -> g |> host(:next) |> ok!() end)
      assert game.phase == :finished

      view = Game.view(game, :host, @t0)
      assert {view.question, view.accepted_answers, view.submissions} == {nil, nil, nil}
    end
  end
end

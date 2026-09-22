# The pure game functions: one intent at a time, and room setup.
#
#   mix run --no-start bench/game.exs
#
# These are the calls `RoomServer` makes before it broadcasts. They should all be
# cheap next to the fan-out in bench/broadcast.exs — this benchmark exists to
# confirm that, so that when a room feels slow we already know which half to look
# at. Scoring is the one that grows with the room, because it folds over every
# submission.

Code.require_file("support/fixtures.exs", __DIR__)

alias Fazoura.Bench.Fixtures
alias Fazoura.Game
alias Fazoura.Game.Pack

Fixtures.banner()

t0 = Fixtures.t0()
sizes = [4, 20, 60, 100]

# A room mid-question with everyone in but "p1", who is the one submitting.
open_rooms =
  Map.new(sizes, fn n ->
    game = Fixtures.game(n, :question)
    {"#{n} players", update_in(game.submissions, &Map.delete(&1, "p1"))}
  end)

Benchee.run(
  %{
    # Validation, normalization and the match, for one answer.
    "submit" => fn game ->
      {:ok, _} =
        Game.handle(game, {:player, "p1"}, {:submit, %{"answer" => "Tunis"}}, t0)
    end,

    # Closing the question: folds the score delta over every submission at once.
    "next (score the question)" => fn game ->
      {:ok, _} = Game.handle(game, :host, :next, t0)
    end,

    # Called on every timer tick while a question is open, on every room.
    "tick (deadline not reached)" => fn game ->
      Game.tick(game, t0)
    end
  },
  inputs: open_rooms,
  time: 3,
  warmup: 1,
  memory_time: 1,
  title: "intents during a question",
  print: [fast_warning: false]
)

# Overrides happen in scoring, one at a time, and each one re-broadcasts.
scored_rooms = Map.new(sizes, fn n -> {"#{n} players", Fixtures.game(n, :scoring)} end)

Benchee.run(
  %{
    "override one submission" => fn game ->
      {:ok, _} =
        Game.handle(
          game,
          :host,
          {:override, %{"player_id" => "p1", "correct" => true}},
          t0
        )
    end
  },
  inputs: scored_rooms,
  time: 3,
  warmup: 1,
  memory_time: 1,
  title: "host override",
  print: [fast_warning: false]
)

# Room setup. `POST /api/rooms` may carry a private quiz inline, so parsing and
# pack-building are on the request path, not just the seed path. A host may pick
# up to 10 quizzes and they are merged into one pool (PROTOCOL.md §6.4).
ten_packs = for i <- 1..10, do: Fixtures.pack(20, "Quiz #{i}")

big_pack_map = %{
  "title" => "Big",
  "questions" =>
    for i <- 1..200 do
      %{
        "id" => "q#{i}",
        "prompt" => "Question #{i}?",
        "accepted_answers" => ["a", "b", "c"],
        "difficulty" => "medium"
      }
    end
}

merged = Pack.merge(ten_packs)

Benchee.run(
  %{
    "Pack.from_map (200 questions)" => fn -> Pack.from_map(big_pack_map) end,
    "Pack.merge (10 quizzes x 20)" => fn -> Pack.merge(ten_packs) end,
    # Includes the shuffle of the whole question order.
    "Game.new (200-question pool)" => fn -> Game.new("BENCH1", merged) end,
    "select_quiz (replaces the pool)" => fn ->
      {:ok, _} = Game.select_quiz(Game.new("BENCH1", Fixtures.pack(1)), merged)
    end
  },
  time: 3,
  warmup: 1,
  memory_time: 1,
  title: "room setup",
  print: [fast_warning: false]
)

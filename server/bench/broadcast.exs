# Broadcast cost: what one state change costs a room.
#
#   mix run --no-start bench/broadcast.exs
#
# Every state change sends a *complete* RoomState snapshot to every connection
# (AGENTS.md §3), and the snapshot is built per recipient because `you` differs.
# So `RoomServer.broadcast/1` is N calls to `Game.view/3`, and each of those sorts
# the player list — twice, once for `players` and once for `submissions`.
#
# The question this answers: where does that stop being free? A 100-player room
# in the scoring phase is the worst case the protocol allows (@max_players).

Code.require_file("support/fixtures.exs", __DIR__)

alias Fazoura.Bench.Fixtures
alias Fazoura.Game

Fixtures.banner()

t0 = Fixtures.t0()

# Room sizes worth knowing: a family, a classroom, a big party, the protocol cap.
sizes = [4, 20, 60, 100]

inputs =
  Map.new(sizes, fn n ->
    game = Fixtures.game(n, :scoring)
    {"#{n} players", %{game: game, recipients: Fixtures.recipients(game)}}
  end)

Benchee.run(
  %{
    # One snapshot, for one player. The unit RoomServer repeats per connection.
    "view/3 (one recipient)" => fn %{game: game} ->
      Game.view(game, {:player, "p1"}, t0)
    end,

    # The whole fan-out: what a single `next`, `submit` or `override` really costs.
    "fan-out (every recipient)" => fn %{game: game, recipients: recipients} ->
      Enum.each(recipients, &Game.view(game, &1, t0))
    end,

    # Fan-out plus the JSON each snapshot turns into on the wire. Phoenix
    # serializes per push, so this is the honest end-to-end number — and it tells
    # us whether the sort or the encoder is the thing to worry about.
    "fan-out + JSON encode" => fn %{game: game, recipients: recipients} ->
      Enum.each(recipients, fn recipient ->
        game |> Game.view(recipient, t0) |> Jason.encode!()
      end)
    end
  },
  inputs: inputs,
  time: 5,
  warmup: 2,
  memory_time: 2,
  print: [fast_warning: false]
)

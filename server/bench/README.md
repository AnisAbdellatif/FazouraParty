# Benchmarks

Benchee scripts for the pure game code. **Not checks** — they are slow and their
numbers depend on the machine, so `scripts/ci.sh` does not run them and CI never
will. Run them by hand when a change touches the hot path, and compare against a
run of `main` on the *same* machine; absolute numbers from someone else's laptop
mean nothing.

```bash
mix bench                                  # all three, ~3 minutes
mix run --no-start bench/broadcast.exs     # just one
```

`--no-start` is deliberate: nothing here needs the Repo or the endpoint, and
starting them would mean a database and a fight over port 4000.

| File | What it measures |
|---|---|
| `broadcast.exs` | `Game.view/3` per recipient, the whole fan-out, and the JSON each snapshot becomes. The protocol sends a complete `RoomState` to every connection on every change, so this is where a room gets expensive. |
| `game.exs` | The intents `RoomServer` handles before it broadcasts — submit, score, tick, override — plus room setup (`Pack.from_map/1`, `Pack.merge/1`, `Game.new/3`). |
| `answer.exs` | `Answer.normalize/1` by script (ASCII, accented Latin, Arabic) and `Answer.correct?/2` against 1, 3 and 10 accepted answers. |

`support/fixtures.exs` builds the rooms. They are bigger and messier than the
test fixtures on purpose: full rooms with tied scores and mixed-script names, so
the leaderboard sort and `String.downcase/1` do the work they would do in a real
room rather than on ASCII with distinct scores.

## What the first run found (16-core dev box, OTP 28)

Recorded so a later run has something to diff against, not as a target.

- **The fan-out dominates, by a lot.** A 100-player room costs ~18 μs to score a
  whole question but ~6.3 ms to build the 101 snapshots, and ~28.7 ms once each
  is JSON-encoded. Intents are ~350× cheaper than telling everyone about them.
- **It is quadratic in players**, as the design implies: N recipients × a snapshot
  that sorts N players twice. 4 players ≈ 71 μs, 100 ≈ 28.7 ms.
- Every submission triggers a broadcast, so a room where 100 people answer at
  once spends seconds of one `RoomServer`'s time on snapshots for a single
  question. Worth knowing before anyone raises `@max_players`.
- `Answer.correct?/2` re-normalizes every accepted answer on every call: a miss
  against 10 accepted spellings is ~57 μs, five times a first-entry hit.
- Room setup is free by comparison — merging 10 quizzes and shuffling a
  200-question pool is ~35 μs, once per room.

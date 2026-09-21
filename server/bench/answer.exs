# Answer matching: the per-submission cost, and what normalization costs by script.
#
#   mix run --no-start bench/answer.exs
#
# `Answer.correct?/2` normalizes the player's answer once, then normalizes every
# accepted answer again on every call — the accepted list is re-normalized per
# submission, per question, for the life of the room. Whether that matters is
# what "accepted answers" below measures.
#
# The scripts are separated because normalization is not uniform work: NFD
# decomposition and the `\p{Mn}` regex do nothing to plain ASCII, real work to
# accented Latin, and the Arabic path additionally has no case to fold.

Code.require_file("support/fixtures.exs", __DIR__)

alias Fazoura.Bench.Fixtures
alias Fazoura.Game.Answer

Fixtures.banner()

Benchee.run(
  %{
    "ascii" => fn -> Answer.normalize("New York City") end,
    "accented latin" => fn -> Answer.normalize("Crème Brûlée à São Paulo") end,
    "arabic" => fn -> Answer.normalize("مدينة تونس العاصمة") end,
    "messy whitespace" => fn -> Answer.normalize("   the    Great   Barrier  Reef \n") end,
    "long (100 chars, the cap)" => fn -> Answer.normalize(String.duplicate("Zürich ", 14)) end
  },
  time: 3,
  warmup: 1,
  memory_time: 1,
  title: "normalize/1 by script",
  print: [fast_warning: false]
)

# One accepted answer versus a generously-spelled one. A question with ten
# accepted spellings pays ten normalizations for every submission it receives.
accepted = %{
  "1 accepted" => ["Tunis"],
  "3 accepted" => ["Tunis", "Tūnis", "تونس"],
  "10 accepted" => [
    "Tunis",
    "Tūnis",
    "تونس",
    "Tunis City",
    "Tunisia",
    "La Goulette",
    "Carthage",
    "Túnez",
    "Tunesien",
    "Tunisi"
  ]
}

Benchee.run(
  %{
    # Worst case on purpose: no match, so every accepted answer is normalized.
    "miss (walks the whole list)" => fn list -> Answer.correct?("Marrakesh", list) end,
    # Best case: the first entry matches and `Enum.any?` stops there.
    "hit on the first entry" => fn list -> Answer.correct?("  TUNIS  ", list) end
  },
  inputs: accepted,
  time: 3,
  warmup: 1,
  memory_time: 1,
  title: "correct?/2 by accepted-answer count",
  print: [fast_warning: false]
)

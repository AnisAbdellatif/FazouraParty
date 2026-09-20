defmodule Fazoura.Game.PackTest do
  @moduledoc """
  Merging the quizzes a host selected into the one pool a round is played from
  (PROTOCOL.md §6.4). The Dart counterpart is `test/core/game/quiz_pool_test.dart`.
  """

  use ExUnit.Case, async: true

  alias Fazoura.Game.Pack

  defp pack(title, ids) do
    Pack.from_map(%{
      "title" => title,
      "questions" =>
        for id <- ids do
          %{
            "id" => id,
            "prompt" => "#{title} #{id}?",
            "accepted_answers" => ["a"],
            "time_limit_ms" => 30_000
          }
        end
    })
  end

  test "one pack is itself, untouched" do
    only = pack("Solo", ["q1", "q2"])

    assert Pack.merge([only]) == only
    assert Enum.map(only.questions, & &1.id) == ["q1", "q2"]
  end

  test "several become one pool with unique ids and every title" do
    merged = Pack.merge([pack("One", ["q1", "q2"]), pack("Two", ["q1"]), pack("Three", ["q1"])])

    assert merged.titles == ["One", "Two", "Three"]
    assert length(merged.questions) == 4

    ids = Enum.map(merged.questions, & &1.id)
    assert length(Enum.uniq(ids)) == 4

    # The prompts still say where each question came from, so nothing is lost
    # by rewriting the ids.
    assert Enum.map(merged.questions, & &1.prompt) ==
             ["One q1?", "One q2?", "Two q1?", "Three q1?"]
  end

  test "defaults come from the first pack, not the last" do
    first = %{
      pack("First", [])
      | default_time_limit_ms: 90_000,
        default_difficulty_multiplier: true
    }

    second = %{pack("Second", []) | default_time_limit_ms: 15_000}

    merged = Pack.merge([first, second])

    assert merged.default_time_limit_ms == 90_000
    assert merged.default_difficulty_multiplier
  end
end

defmodule Fazoura.QuizFixtures do
  @moduledoc "Test helpers for quizzes and packs."

  alias Fazoura.Game.Pack

  def owner_key, do: "test-owner-key-aaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  def other_key, do: "test-other-key-bbbbbbbbbbbbbbbbbbbbbbbbbbbb"

  @doc "A small in-memory pack for room/channel tests that don't need the database."
  def pack do
    Pack.from_map(%{
      "title" => "General Knowledge",
      "questions" =>
        for i <- 1..3 do
          %{
            "id" => "q#{i}",
            "prompt" => "Question #{i}?",
            "accepted_answers" => ["Answer #{i}"],
            "time_limit_ms" => 30_000
          }
        end
    })
  end

  @doc "A valid quiz document (QUIZ_FORMAT.md §2) with string keys, as JSON decodes it."
  def quiz_params(attrs \\ %{}) do
    Map.merge(
      %{
        "format_version" => 1,
        "title" => "Movie Night",
        "category" => "movies",
        "questions" => [
          %{
            "type" => "text",
            "prompt" => "Who directed Jurassic Park?",
            "accepted_answers" => ["Steven Spielberg", "Spielberg"],
            "difficulty" => "easy"
          }
        ]
      },
      attrs
    )
  end
end

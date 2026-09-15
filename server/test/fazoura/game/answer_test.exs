defmodule Fazoura.Game.AnswerTest do
  use ExUnit.Case, async: true

  alias Fazoura.Game.Answer
  alias Fazoura.ProtocolFixtures

  @fixtures ProtocolFixtures.load!("normalize.json")

  for %{"input" => input, "output" => output} <- @fixtures["normalize"] do
    test "normalize #{inspect(input)}" do
      assert Answer.normalize(unquote(input)) == unquote(output)
    end
  end

  for %{"answer" => answer, "accepted" => accepted, "correct" => correct} <- @fixtures["match"] do
    test "#{inspect(answer)} against #{inspect(accepted)} is #{correct}" do
      assert Answer.correct?(unquote(answer), unquote(accepted)) == unquote(correct)
    end
  end
end

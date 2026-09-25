defmodule Fazoura.Moderation.ProfanityTest do
  use ExUnit.Case, async: true

  alias Fazoura.Moderation.Profanity

  test "catches the obvious, and the obvious ways round it" do
    for text <- [
          "fuck",
          "F.U.C.K",
          "fuuuuck off",
          "f4ggot",
          "Ya kahba",
          "9a7ba",
          "zebi",
          "salope",
          "زب",
          "sh1t",
          # A zero-width space and a zero-width joiner spliced in to break the word
          # across a token boundary; invisible, so the name still reads "fuck".
          "fu\u{200B}ck",
          "f\u{200D}u\u{200D}c\u{200D}k"
        ] do
      refute Profanity.clean?(text), inspect(text)
    end
  end

  test "leaves innocent words alone, including the ones that contain a bad one" do
    for text <- [
          "Sam",
          "assassin",
          "Scunthorpe",
          "therapist",
          "unique",
          "cocktail",
          "Dick Cheney",
          "pass",
          "دخول",
          "حزب",
          "زبدة",
          "Montevideo",
          nil
        ] do
      assert Profanity.clean?(text), inspect(text)
    end
  end
end

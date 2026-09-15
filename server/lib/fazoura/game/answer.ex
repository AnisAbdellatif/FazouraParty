defmodule Fazoura.Game.Answer do
  @moduledoc """
  Automatic answer matching (PROTOCOL.md §8).

  Normalized exact match only — no fuzzy matching. The host override is the second pass.
  """

  @doc "NFD, strip combining marks, lower-case, trim, collapse internal whitespace."
  @spec normalize(String.t()) :: String.t()
  def normalize(text) when is_binary(text) do
    text
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/\p{Mn}/u, "")
    |> String.downcase()
    |> String.split()
    |> Enum.join(" ")
  end

  @spec correct?(String.t(), [String.t()]) :: boolean()
  def correct?(answer, accepted_answers) do
    normalized = normalize(answer)
    Enum.any?(accepted_answers, &(normalize(&1) == normalized))
  end
end

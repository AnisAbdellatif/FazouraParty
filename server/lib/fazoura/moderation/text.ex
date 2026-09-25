defmodule Fazoura.Moderation.Text do
  @moduledoc """
  How `Fazoura.Moderation.Profanity` reads text, so the word list and what it is
  compared with are read the same way — at compile time for the list, at run time for
  a name or an answer.
  """

  # Digits and symbols read as letters. The raw form is checked as well, because in
  # Tunisian Derja written in Latin letters 3, 7 and 9 *are* letters.
  @leet %{
    "0" => "o",
    "1" => "i",
    "3" => "e",
    "4" => "a",
    "5" => "s",
    "7" => "t",
    "@" => "a",
    "$" => "s"
  }

  @doc "Marks off, Arabic tatweel out, invisibles out, lower case, repeated letters collapsed."
  @spec normalize(String.t()) :: String.t()
  def normalize(text) do
    text
    # `\p{Cf}` are the format characters — zero-width space/joiner/non-joiner, the BOM,
    # the bidi controls: invisible, so a name reads the same with them spliced into a
    # slur to break it across the token boundary. Stripped with the combining marks and
    # the tatweel so what is compared is what is seen.
    |> :unicode.characters_to_nfd_binary()
    |> String.replace(~r/[\p{Mn}\p{Cf}\x{0640}]/u, "")
    |> String.downcase()
    |> collapse()
  end

  @doc "`text` with leetspeak read as letters."
  @spec leet(String.t()) :: String.t()
  def leet(text) do
    text
    |> String.graphemes()
    |> Enum.map_join(&Map.get(@leet, &1, &1))
    |> collapse()
  end

  @doc "The words in `text`: runs of letters and digits."
  @spec tokens(String.t()) :: [String.t()]
  def tokens(text), do: String.split(text, ~r/[^\p{L}\p{N}]+/u, trim: true)

  defp collapse(text), do: String.replace(text, ~r/(.)\1+/u, "\\1")
end

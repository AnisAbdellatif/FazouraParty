defmodule Fazoura.Moderation.Profanity do
  @moduledoc """
  Whether a display name or an answer contains a word a public room will not show
  (PROTOCOL.md §3.5).

  The list is `priv/moderation/blocked_words.txt`, compiled in. Matching ignores case,
  accents and leetspeak and collapses repeated letters (`Fazoura.Moderation.Text`), so
  the list only needs the plain spelling. An entry matches as a whole word, so "ass"
  does not catch "assassin"; an entry written `*stem` also matches inside words and
  across separators, which is what catches "f.u.c.k" and "fuckface"; and `!word` names an
  innocent word a stem would otherwise catch ("Scunthorpe").

  Pure, so `Fazoura.Game` can ask it. It is a floor, not a filter that understands
  language: the report button and the host removing a player handle what gets past it.
  """

  alias Fazoura.Moderation.Text

  @path Path.join(:code.priv_dir(:fazoura), "moderation/blocked_words.txt")
  @external_resource @path

  entries =
    @path
    |> File.read!()
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == "" or String.starts_with?(&1, "#")))

  @stems for "*" <> stem <- entries, do: Text.normalize(stem)
  @allowed MapSet.new(for "!" <> word <- entries, do: Text.normalize(word))
  @words MapSet.new(
           for entry <- entries,
               not String.starts_with?(entry, ["*", "!"]),
               do: Text.normalize(entry)
         )

  @doc "True when `text` contains nothing on the list."
  @spec clean?(String.t() | nil) :: boolean()
  def clean?(nil), do: true

  def clean?(text) when is_binary(text) do
    base = Text.normalize(text)
    not Enum.any?(Enum.uniq([base, Text.leet(base)]), &blocked?/1)
  end

  defp blocked?(text) do
    tokens = text |> Text.tokens() |> Enum.reject(&MapSet.member?(@allowed, &1))
    squashed = Enum.join(tokens)

    Enum.any?(tokens, &MapSet.member?(@words, &1)) or
      Enum.any?(@stems, &String.contains?(squashed, &1))
  end
end

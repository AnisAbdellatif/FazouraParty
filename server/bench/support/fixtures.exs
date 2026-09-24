defmodule Fazoura.Bench.Fixtures do
  @moduledoc """
  Rooms and packs for the benchmarks in `bench/`.

  Deliberately not in `test/support`: these build *large* states (full rooms, 200
  questions) that no test wants, and they are shaped to be realistic rather than
  minimal — varied scores so the leaderboard sort has work to do, mixed scripts so
  `String.downcase/1` and NFD are not measured on ASCII alone.
  """

  alias Fazoura.Game
  alias Fazoura.Game.Pack

  # A fixed instant, so nothing here depends on the wall clock.
  @t0 1_000_000
  @difficulties ~w(easy medium hard)

  # Names people actually type: Latin, accented Latin, Arabic, and an emoji, so the
  # sort key (`String.downcase/1`) is exercised on more than ASCII.
  @names ~w(Sam Amina José Zoë Nour ياسمين خالد Björn Chloé عمر Ines Théo)

  def t0, do: @t0

  @doc "A pack of `count` questions, cycling difficulty so every scoring path is exercised."
  def pack(count \\ 20, title \\ "Bench") do
    Pack.from_map(%{
      "title" => title,
      "questions" =>
        for i <- 1..count do
          %{
            "id" => "q#{i}",
            "type" => "text",
            "prompt" => "Which capital city is question #{i} about?",
            "accepted_answers" => ["Tunis", "Tūnis", "تونس"],
            "difficulty" => Enum.at(@difficulties, rem(i, 3)),
            "time_limit_ms" => 30_000
          }
        end
    })
  end

  @doc """
  A room of `players` people, in `phase`, with every player's answer already in —
  except, mid-question, the answer of "p1".

  Scores are spread (and deliberately tied in places) so `players_view/1` sorts on
  the name tiebreak as often as on the score.
  """
  def game(players, phase \\ :question, questions \\ 20) do
    :lobby
    |> new_game(players, questions)
    |> advance_to(phase)
  end

  defp new_game(:lobby, players, questions) do
    game =
      Enum.reduce(1..players, Game.new("BENCH1", pack(questions)), fn i, game ->
        {:ok, game} = Game.add_player(game, player_id(i), player_name(i), rem(i * 37, 360))
        game
      end)

    # Ties every third player, so the name comparison actually runs.
    Enum.reduce(1..players, game, fn i, game ->
      put_in(game.players[player_id(i)].score, rem(i, 3) * 7 + div(i, 3))
    end)
  end

  defp advance_to(game, :lobby), do: game

  # A question ends by itself once everybody has answered, so a room left in
  # `:question` is one where "p1" has not: the answer a benchmark then submits.
  defp advance_to(game, :question) do
    {:ok, game} = Game.handle(game, :host, :next, @t0)
    Enum.reduce(Map.keys(game.players) -- ["p1"], game, &submit(&2, &1))
  end

  defp advance_to(game, :scoring) do
    {:ok, game} = Game.handle(game, :host, :next, @t0)
    Enum.reduce(Map.keys(game.players), game, &submit(&2, &1))
  end

  defp advance_to(game, :leaderboard) do
    {:ok, game} = Game.handle(advance_to(game, :scoring), :host, :next, @t0)
    game
  end

  @doc "One submission, half of them right, so both scoring branches are hit."
  def submit(game, id, now \\ @t0) do
    answer = if :erlang.phash2(id, 2) == 0, do: "  Tūnis ", else: "Carthage"

    {:ok, game} =
      Game.handle(game, {:player, id}, {:submit, %{"answer" => answer}}, now)

    game
  end

  def player_id(i), do: "p#{i}"
  def player_name(i), do: Enum.at(@names, rem(i, length(@names))) <> " #{i}"

  @doc "Every recipient the room shell would build a view for: the host plus each player."
  def recipients(game), do: [:host | Enum.map(Map.keys(game.players), &{:player, &1})]

  @doc "Banner naming what is on the machine, so a pasted result says where it came from."
  def banner do
    IO.puts([
      "\n",
      IO.ANSI.bright(),
      "Elixir #{System.version()} / OTP #{System.otp_release()} / ",
      "#{System.schedulers_online()} schedulers",
      IO.ANSI.reset(),
      "\n"
    ])
  end
end

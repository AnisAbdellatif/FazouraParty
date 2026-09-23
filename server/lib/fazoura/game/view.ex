defmodule Fazoura.Game.View do
  @moduledoc """
  What each connection is sent: the complete `RoomState` snapshot of a game as one
  recipient sees it (PROTOCOL.md §5.1), with the visibility rules of §7 applied.

  Pure, like `Fazoura.Game`, and kept apart from it: the game decides what happens, this
  decides who may see what. Every snapshot is complete, never a delta, so this is the
  whole of the wire format for a room. The LAN host builds the same one in
  `app/lib/core/game/game_view.dart`.
  """

  alias Fazoura.Game

  @doc "The complete `RoomState` snapshot of `game` as `recipient` sees it, at `now`."
  @spec room_state(Game.t(), Game.actor() | {:host, boolean()}, integer()) :: map()
  def room_state(game, recipient, now) do
    question = if game.phase in [:lobby, :finished], do: nil, else: Game.current_question(game)
    # Same for every role: the host may be playing, so nobody gets an early look (§7).
    revealed? = game.phase in [:scoring, :leaderboard]
    constants = Game.constants()

    %{
      protocol_version: Game.protocol_major(),
      protocol_minor: Game.protocol_minor(),
      room_code: game.room_code,
      mode: Atom.to_string(game.mode),
      listed: game.listed,
      phase: Atom.to_string(game.phase),
      server_time: now,
      pack_titles: if(game.pack.questions == [], do: [], else: game.pack.titles),
      question_index: game.question_index,
      question_count: game.settings.question_count,
      game_number: game.game_number,
      settings: %{
        question_count: game.settings.question_count,
        time_limit_ms: game.settings.time_limit_ms,
        difficulty_multiplier: game.settings.difficulty_multiplier,
        max_question_count: Game.max_question_count(game),
        difficulties: game.settings.difficulties,
        available_difficulties: game.settings.available_difficulties,
        min_time_limit_ms: constants["min_time_limit_ms"],
        max_time_limit_ms: constants["max_time_limit_ms"]
      },
      question: question && question_view(game, question),
      deadline: game.deadline,
      paused_remaining_ms: game.paused_remaining_ms,
      accepted_answers: if(question && revealed?, do: question.accepted_answers),
      players: players_view(game),
      you: you_view(game, recipient, question),
      submissions: if(question && revealed?, do: submissions_view(game))
    }
  end

  defp question_view(game, question) do
    points = Game.points(game, question)

    question
    |> Map.take([:id, :type, :prompt, :image_url, :time_limit_ms, :difficulty])
    |> Map.put(:points, Map.put(points, :skipped, Game.skip_points()))
  end

  defp players_view(game) do
    tracks_submissions? = game.phase in [:question, :scoring, :leaderboard]

    game
    |> sorted_players()
    |> Enum.map(fn p ->
      # Listed field by field rather than merged over the player, so anything
      # the server keeps for its own bookkeeping — `disconnected_at` — cannot
      # reach a broadcast just by existing on the struct (PROTOCOL.md §5.1).
      %{
        id: p.id,
        name: p.name,
        score: p.score,
        connected: p.connected,
        avatar_hue: p.avatar_hue,
        has_submitted: tracks_submissions? and Map.has_key?(game.submissions, p.id),
        is_host: p.id == game.host_player_id
      }
    end)
  end

  defp sorted_players(game) do
    game.players
    |> Map.values()
    |> Enum.sort_by(&{-&1.score, String.downcase(&1.name)})
  end

  # Everyone the question was put to gets a row, so the scoring screen never has to know
  # what saying nothing costs: `answer: nil` is the player who let it go by.
  defp submissions_view(game) do
    for player <- sorted_players(game),
        change = Game.question_delta(game, player.id) do
      submission = game.submissions[player.id]

      %{
        player_id: player.id,
        answer: submission[:answer],
        auto_correct: submission[:auto_correct] || false,
        override: submission[:override],
        correct: submission != nil and Game.correct?(submission),
        delta: change
      }
    end
  end

  # `role` reports who holds the host role *now*, not how this connection
  # authenticated. The two differ after a transfer or promotion (PROTOCOL.md
  # §3.4): a promoted player is still connected as a player, and a demoted host
  # is still connected as the host. Either way the client has to be told the
  # truth, or the new host never learns it is in charge and the old one keeps
  # showing controls it can no longer use.
  #
  # `{:host, holder?}` is how the room shell says whether the connection that
  # authenticated as host still holds the role; the game state alone cannot tell,
  # because `host_player_id: nil` means both "the host isn't playing" and "the
  # role has moved to someone else".
  defp you_view(game, :host, question), do: you_view(game, {:host, true}, question)

  defp you_view(game, {:host, holder?}, question) do
    %{
      do_you_view(game, game.host_player_id, question)
      | role: if(holder?, do: "host", else: "player")
    }
  end

  defp you_view(game, {:player, id}, question) do
    %{
      do_you_view(game, id, question)
      | role: if(game.host_player_id == id, do: "host", else: "player")
    }
  end

  defp do_you_view(game, id, question) do
    %{
      role: "player",
      player_id: id,
      # Filled in by the room shell for the one recipient who has just been given
      # the role (PROTOCOL.md §5.1); the game itself has no tokens.
      host_token: nil,
      submission: own_submission_view(game, id, question)
    }
  end

  # The recipient's own submission, or — from scoring on — the row that tells a player
  # who said nothing what that cost them.
  defp own_submission_view(_game, nil, _question), do: nil

  defp own_submission_view(game, id, question) do
    scored? = game.phase in [:scoring, :leaderboard]

    case question && game.submissions[id] do
      nil ->
        if scored? and MapSet.member?(game.asked, id),
          do: %{answer: nil, correct: false, delta: Game.skip_points()}

      submission ->
        %{
          answer: submission.answer,
          correct: if(scored?, do: Game.correct?(submission)),
          delta: if(scored?, do: Game.delta(submission))
        }
    end
  end
end

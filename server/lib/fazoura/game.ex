defmodule Fazoura.Game do
  @moduledoc """
  Pure game logic for one room (PROTOCOL.md §4–§9).

  No processes, timers or clocks: every function takes the state (and `now` where time
  matters) and returns a new state. `Fazoura.Rooms.RoomServer` is the thin process shell
  that owns the state, supplies the clock and delivers views to sockets.
  """

  alias Fazoura.Game.{Answer, Pack}

  @protocol_version 4
  @max_question_count 20
  # Points = wager × multiplier when the difficulty bonus is on (PROTOCOL.md §9).
  @multipliers %{"easy" => 1, "medium" => 2, "hard" => 3}
  @min_time_limit_ms 10_000
  @max_time_limit_ms 120_000
  @default_time_limit_ms 30_000
  @max_players 100
  @max_name_length 20
  @max_answer_length 100
  @min_wager 1
  @max_wager 10

  @type phase :: :lobby | :question | :scoring | :leaderboard | :finished
  @type actor :: :host | {:player, String.t()}
  @type intent ::
          {:submit, map()}
          | :next
          | :pause
          | :resume
          | {:override, map()}
          | {:configure, map()}
          | :rematch
  @type error :: {:error, atom()}

  @type player :: %{
          id: String.t(),
          name: String.t(),
          score: integer(),
          connected: boolean(),
          avatar_hue: non_neg_integer()
        }
  @type submission :: %{
          answer: String.t(),
          wager: pos_integer(),
          auto_correct: boolean(),
          override: boolean() | nil
        }

  @type t :: %__MODULE__{
          room_code: String.t(),
          mode: :cloud | :lan,
          pack: Pack.t(),
          phase: phase(),
          question_index: non_neg_integer() | nil,
          deadline: integer() | nil,
          paused_remaining_ms: non_neg_integer() | nil,
          host_player_id: String.t() | nil,
          settings: %{
            question_count: pos_integer(),
            time_limit_ms: pos_integer(),
            difficulty_multiplier: boolean()
          },
          game_number: pos_integer(),
          question_offset: non_neg_integer(),
          players: %{String.t() => player()},
          submissions: %{String.t() => submission()}
        }

  @enforce_keys [:room_code, :pack, :settings]
  defstruct [
    :room_code,
    :pack,
    :settings,
    game_number: 1,
    # Index into the pack where the current game starts; advances on rematch.
    question_offset: 0,
    mode: :cloud,
    phase: :lobby,
    question_index: nil,
    deadline: nil,
    paused_remaining_ms: nil,
    host_player_id: nil,
    players: %{},
    submissions: %{}
  ]

  @spec protocol_version() :: pos_integer()
  def protocol_version, do: @protocol_version

  @spec new(String.t(), Pack.t(), keyword()) :: t()
  def new(room_code, %Pack{} = pack, opts \\ []) do
    %__MODULE__{
      room_code: room_code,
      pack: pack,
      mode: Keyword.get(opts, :mode, :cloud),
      settings: default_settings(pack)
    }
  end

  # Whole pack, at the first question's time limit (clamped to the allowed range).
  defp default_settings(pack) do
    time =
      case {pack.default_time_limit_ms, pack.questions} do
        {ms, _} when is_integer(ms) -> ms
        {nil, [first | _]} -> first.time_limit_ms
        {nil, []} -> @default_time_limit_ms
      end

    %{
      question_count: min(length(pack.questions), @max_question_count),
      time_limit_ms: time |> max(@min_time_limit_ms) |> min(@max_time_limit_ms),
      difficulty_multiplier: pack.default_difficulty_multiplier
    }
  end

  ## Players

  @spec add_player(t(), String.t(), term(), non_neg_integer()) :: {:ok, t()} | error()
  def add_player(game, id, name, avatar_hue \\ 0)

  def add_player(%__MODULE__{} = game, id, name, avatar_hue) when is_binary(name) do
    name = String.trim(name)

    cond do
      String.length(name) not in 1..@max_name_length -> {:error, :invalid_name}
      map_size(game.players) >= @max_players -> {:error, :room_full}
      name_taken?(game, name) -> {:error, :name_taken}
      true -> {:ok, put_in(game.players[id], new_player(id, name, avatar_hue))}
    end
  end

  def add_player(_game, _id, _name, _avatar_hue), do: {:error, :invalid_name}

  defp new_player(id, name, avatar_hue),
    do: %{id: id, name: name, score: 0, connected: false, avatar_hue: avatar_hue}

  @doc """
  A random avatar hue (0..359), kept as far as possible from hues already used in
  the room. `random` must return an integer in 0..359 (injectable for tests).
  """
  @spec pick_avatar_hue(t(), (-> non_neg_integer())) :: non_neg_integer()
  def pick_avatar_hue(game, random \\ fn -> :rand.uniform(360) - 1 end) do
    used = Enum.map(game.players, fn {_id, player} -> player.avatar_hue end)
    candidates = for _ <- 1..12, do: random.()
    Enum.max_by(candidates, &min_hue_distance(&1, used))
  end

  defp min_hue_distance(_hue, []), do: 360

  defp min_hue_distance(hue, used) do
    used
    |> Enum.map(fn other -> min(abs(hue - other), 360 - abs(hue - other)) end)
    |> Enum.min()
  end

  @doc """
  Makes the host a player too. A no-op if the host already plays (the name is ignored).
  """
  @spec add_host_player(t(), String.t(), term(), non_neg_integer()) :: {:ok, t()} | error()
  def add_host_player(game, id, name, avatar_hue \\ 0)

  def add_host_player(%__MODULE__{host_player_id: nil} = game, id, name, avatar_hue) do
    with {:ok, game} <- add_player(game, id, name, avatar_hue) do
      {:ok, %{game | host_player_id: id}}
    end
  end

  def add_host_player(game, _id, _name, _avatar_hue), do: {:ok, game}

  @spec player?(t(), String.t() | nil) :: boolean()
  def player?(game, id), do: Map.has_key?(game.players, id)

  @spec set_connected(t(), String.t(), boolean()) :: t()
  def set_connected(game, id, connected?) do
    if player?(game, id), do: put_in(game.players[id].connected, connected?), else: game
  end

  defp name_taken?(game, name) do
    key = String.downcase(name)
    Enum.any?(game.players, fn {_id, p} -> String.downcase(p.name) == key end)
  end

  ## Intents

  @spec handle(t(), actor(), intent(), integer()) :: {:ok, t()} | error()
  def handle(game, {:player, id}, {:submit, payload}, now) do
    with :ok <- require_player(game, id),
         :ok <- require_phase(game, [:question]),
         :ok <- require_running(game),
         :ok <- require_before_deadline(game, now),
         :ok <- require_no_submission(game, id),
         {:ok, answer} <- validate_answer(payload["answer"]),
         {:ok, wager} <- validate_wager(payload["wager"]) do
      question = current_question(game)

      submission = %{
        answer: answer,
        wager: wager,
        auto_correct: Answer.correct?(answer, question.accepted_answers),
        override: nil,
        multiplier: multiplier(game, question)
      }

      {:ok, put_in(game.submissions[id], submission)}
    end
  end

  def handle(_game, {:player, _id}, _host_intent, _now), do: {:error, :not_host}
  def handle(%{host_player_id: nil}, :host, {:submit, _payload}, _now), do: {:error, :not_player}

  def handle(game, :host, {:submit, _payload} = intent, now),
    do: handle(game, {:player, game.host_player_id}, intent, now)

  def handle(game, :host, :next, now) do
    case game.phase do
      :lobby -> {:ok, start_question(game, 0, now)}
      :question -> {:ok, score_question(game)}
      :scoring -> {:ok, %{game | phase: :leaderboard}}
      :leaderboard -> {:ok, after_leaderboard(game, now)}
      :finished -> {:error, :invalid_phase}
    end
  end

  def handle(game, :host, :pause, now) do
    with :ok <- require_phase(game, [:question]),
         :ok <- require_running(game) do
      {:ok, %{game | deadline: nil, paused_remaining_ms: max(game.deadline - now, 0)}}
    end
  end

  def handle(game, :host, :resume, now) do
    with :ok <- require_phase(game, [:question]) do
      case game.paused_remaining_ms do
        nil -> {:error, :not_paused}
        ms -> {:ok, %{game | deadline: now + ms, paused_remaining_ms: nil}}
      end
    end
  end

  def handle(game, :host, {:override, payload}, _now) do
    with :ok <- require_phase(game, [:scoring, :leaderboard]),
         {:ok, id, correct} <- validate_override(payload),
         :ok <- require_player(game, id),
         {:ok, old} <- fetch_submission(game, id) do
      new = %{old | override: correct}
      score_change = delta(new) - delta(old)

      game =
        game
        |> put_in([Access.key!(:submissions), id], new)
        |> update_in([Access.key!(:players), id, :score], &(&1 + score_change))

      {:ok, game}
    end
  end

  def handle(game, :host, {:configure, payload}, _now) do
    with :ok <- require_phase(game, [:lobby]),
         {:ok, settings} <- validate_settings(game, payload) do
      {:ok, %{game | settings: settings}}
    end
  end

  def handle(game, :host, :rematch, _now) do
    with :ok <- require_phase(game, [:finished]) do
      players = Map.new(game.players, fn {id, player} -> {id, %{player | score: 0}} end)
      offset = rem(game.question_offset + game.settings.question_count, pack_size(game))

      {:ok,
       %{
         game
         | phase: :lobby,
           question_index: nil,
           deadline: nil,
           paused_remaining_ms: nil,
           submissions: %{},
           players: players,
           game_number: game.game_number + 1,
           question_offset: offset
       }}
    end
  end

  def handle(_game, _actor, _intent, _now), do: {:error, :invalid_payload}

  @doc "Ends the current question if its deadline has passed. Call before handling anything."
  @spec tick(t(), integer()) :: t()
  def tick(%__MODULE__{phase: :question, deadline: deadline} = game, now)
      when is_integer(deadline) and now >= deadline,
      do: score_question(game)

  def tick(game, _now), do: game

  @doc "The next time `tick/2` must run, if any."
  @spec deadline(t()) :: integer() | nil
  def deadline(%__MODULE__{phase: :question, deadline: deadline}), do: deadline
  def deadline(_game), do: nil

  ## Scoring

  @spec delta(submission()) :: integer()
  def delta(submission) do
    points = submission.wager * Map.get(submission, :multiplier, 1)
    if correct?(submission), do: points, else: -points
  end

  @doc "Score multiplier for `question` under the current settings."
  @spec multiplier(t(), Pack.Question.t()) :: pos_integer()
  def multiplier(%__MODULE__{settings: %{difficulty_multiplier: true}}, question),
    do: Map.fetch!(@multipliers, question.difficulty)

  def multiplier(_game, _question), do: 1

  defp correct?(%{override: nil, auto_correct: auto}), do: auto
  defp correct?(%{override: override}), do: override

  defp start_question(game, index, now) do
    %{
      game
      | phase: :question,
        question_index: index,
        deadline: now + game.settings.time_limit_ms,
        paused_remaining_ms: nil,
        submissions: %{}
    }
  end

  defp score_question(game) do
    players =
      Enum.reduce(game.submissions, game.players, fn {id, submission}, players ->
        update_in(players, [id, :score], &(&1 + delta(submission)))
      end)

    %{game | phase: :scoring, players: players, deadline: nil, paused_remaining_ms: nil}
  end

  defp after_leaderboard(game, now) do
    next = game.question_index + 1

    if next < game.settings.question_count,
      do: start_question(game, next, now),
      else: %{game | phase: :finished, submissions: %{}}
  end

  ## Validation

  defp require_player(game, id),
    do: if(player?(game, id), do: :ok, else: {:error, :unknown_player})

  defp require_phase(game, phases),
    do: if(game.phase in phases, do: :ok, else: {:error, :invalid_phase})

  defp require_running(%{paused_remaining_ms: nil}), do: :ok
  defp require_running(_game), do: {:error, :paused}

  defp require_before_deadline(%{deadline: deadline}, now) when now < deadline, do: :ok
  defp require_before_deadline(_game, _now), do: {:error, :invalid_phase}

  defp require_no_submission(game, id),
    do: if(Map.has_key?(game.submissions, id), do: {:error, :already_submitted}, else: :ok)

  defp fetch_submission(game, id) do
    case Map.fetch(game.submissions, id) do
      {:ok, submission} -> {:ok, submission}
      :error -> {:error, :no_submission}
    end
  end

  defp validate_answer(answer) when is_binary(answer) do
    answer = String.trim(answer)

    if String.length(answer) in 1..@max_answer_length,
      do: {:ok, answer},
      else: {:error, :invalid_answer}
  end

  defp validate_answer(_answer), do: {:error, :invalid_answer}

  defp validate_wager(wager) when is_integer(wager) and wager in @min_wager..@max_wager,
    do: {:ok, wager}

  defp validate_wager(_wager), do: {:error, :invalid_wager}

  defp validate_override(%{"player_id" => id, "correct" => correct})
       when is_binary(id) and is_boolean(correct),
       do: {:ok, id, correct}

  defp validate_override(_payload), do: {:error, :invalid_payload}

  defp validate_settings(game, %{
         "question_count" => count,
         "time_limit_ms" => time,
         "difficulty_multiplier" => bonus
       })
       when is_integer(count) and is_integer(time) and is_boolean(bonus) do
    if count in 1..max_question_count(game) and
         time in @min_time_limit_ms..@max_time_limit_ms,
       do: {:ok, %{question_count: count, time_limit_ms: time, difficulty_multiplier: bonus}},
       else: {:error, :invalid_settings}
  end

  defp validate_settings(_game, _payload), do: {:error, :invalid_settings}

  defp pack_size(game), do: length(game.pack.questions)

  defp max_question_count(game), do: min(pack_size(game), @max_question_count)

  ## Views (PROTOCOL.md §5.1, §7)

  @doc "The complete `RoomState` snapshot as seen by `recipient`."
  @spec view(t(), actor(), integer()) :: map()
  def view(game, recipient, now) do
    question = if game.phase in [:lobby, :finished], do: nil, else: current_question(game)
    # Same for every role: the host may be playing, so nobody gets an early look (§7).
    revealed? = game.phase in [:scoring, :leaderboard]

    %{
      protocol_version: @protocol_version,
      room_code: game.room_code,
      mode: Atom.to_string(game.mode),
      phase: Atom.to_string(game.phase),
      server_time: now,
      pack_title: game.pack.title,
      question_index: game.question_index,
      question_count: game.settings.question_count,
      game_number: game.game_number,
      settings: %{
        question_count: game.settings.question_count,
        time_limit_ms: game.settings.time_limit_ms,
        difficulty_multiplier: game.settings.difficulty_multiplier,
        max_question_count: max_question_count(game),
        min_time_limit_ms: @min_time_limit_ms,
        max_time_limit_ms: @max_time_limit_ms
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

  # The pack is played from `question_offset`, wrapping around, at the host's time limit.
  defp current_question(game) do
    index = rem(game.question_offset + game.question_index, pack_size(game))
    %{Enum.at(game.pack.questions, index) | time_limit_ms: game.settings.time_limit_ms}
  end

  defp question_view(game, question) do
    question
    |> Map.take([:id, :type, :prompt, :image_url, :time_limit_ms, :difficulty])
    |> Map.put(:multiplier, multiplier(game, question))
  end

  defp players_view(game) do
    tracks_submissions? = game.phase in [:question, :scoring, :leaderboard]

    game
    |> sorted_players()
    |> Enum.map(fn p ->
      Map.merge(p, %{
        has_submitted: tracks_submissions? and Map.has_key?(game.submissions, p.id),
        is_host: p.id == game.host_player_id
      })
    end)
  end

  defp sorted_players(game) do
    game.players
    |> Map.values()
    |> Enum.sort_by(&{-&1.score, String.downcase(&1.name)})
  end

  defp submissions_view(game) do
    for player <- sorted_players(game),
        submission = game.submissions[player.id] do
      %{
        player_id: player.id,
        answer: submission.answer,
        wager: submission.wager,
        auto_correct: submission.auto_correct,
        override: submission.override,
        correct: correct?(submission),
        multiplier: Map.get(submission, :multiplier, 1),
        delta: delta(submission)
      }
    end
  end

  defp you_view(game, :host, question),
    do: %{you_view(game, {:player, game.host_player_id}, question) | role: "host"}

  defp you_view(game, {:player, id}, question) do
    submission = question && game.submissions[id]
    scored? = game.phase in [:scoring, :leaderboard]

    %{
      role: "player",
      player_id: id,
      submission:
        submission &&
          %{
            answer: submission.answer,
            wager: submission.wager,
            correct: if(scored?, do: correct?(submission)),
            delta: if(scored?, do: delta(submission))
          }
    }
  end
end

defmodule Fazoura.Game do
  @moduledoc """
  Pure game logic for one room (PROTOCOL.md §4–§9).

  No processes, timers or clocks: every function takes the state (and `now` where time
  matters) and returns a new state. `Fazoura.Rooms.RoomServer` is the thin process shell
  that owns the state, supplies the clock and delivers views to sockets.
  """

  alias Fazoura.Game.{Answer, Pack}

  # The protocol is versioned major.minor (PROTOCOL.md §1). The major is the
  # compatibility boundary and the only part on the wire: a client may play
  # against any server sharing its major, so a change that adds nothing a client
  # must understand — a new server-side rule, a field nobody has to read — moves
  # the minor and leaves every installed app working. Changing or removing
  # anything a client already relies on moves the major, and that is a cutover.
  @protocol_major 9
  @protocol_minor 3
  # Points per question by difficulty (PROTOCOL.md §9). A wrong answer costs more on an
  # easy question than on a hard one: you are expected to know the easy ones, and a hard
  # one is worth a guess. Letting the question go by costs @skip_points whatever its
  # difficulty, so saying nothing is never the cheapest way out of a question you should
  # have known.
  @points %{
    "easy" => %{right: 10, wrong: -15},
    "medium" => %{right: 25, wrong: -10},
    "hard" => %{right: 50, wrong: -5}
  }
  # Every question scores the same when the host turns difficulty scoring off.
  @flat_points %{right: 10, wrong: -10}
  @skip_points -10
  # How long a question keeps waiting for a player whose connection has gone.
  # A locked screen or a walk past a thick wall drops the socket for a few
  # seconds while the player is still standing there, and being dropped already
  # costs them the skip penalty — losing the question to a blip as well would be
  # the game's fault, not theirs. Longer than a reconnect, far shorter than the
  # shortest question.
  @waiting_grace_ms 5_000
  @min_time_limit_ms 10_000
  @max_time_limit_ms 120_000
  @default_time_limit_ms 30_000
  @max_players 100
  @max_name_length 20
  @max_answer_length 100
  @difficulties ~w(easy medium hard)

  @type phase :: :lobby | :question | :scoring | :leaderboard | :finished
  @type actor :: :host | {:player, String.t()}
  @type intent ::
          {:submit, map()}
          | {:select_quiz, Pack.t()}
          | :next
          | :pause
          | :resume
          | {:override, map()}
          | {:configure, map()}
          | :rematch
          | {:transfer, map()}
  @type error :: {:error, atom()}

  @type player :: %{
          id: String.t(),
          name: String.t(),
          score: integer(),
          connected: boolean(),
          # When their connection went away, so a question knows whether it is
          # still worth waiting for them. Never leaves the server.
          disconnected_at: integer() | nil,
          avatar_hue: non_neg_integer()
        }
  @type points :: %{right: integer(), wrong: integer()}
  @type submission :: %{
          answer: String.t(),
          auto_correct: boolean(),
          override: boolean() | nil,
          points: points()
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
            question_count: non_neg_integer(),
            time_limit_ms: pos_integer(),
            difficulty_multiplier: boolean(),
            difficulties: [String.t()],
            available_difficulties: [String.t()]
          },
          game_number: pos_integer(),
          question_offset: non_neg_integer(),
          question_order: [non_neg_integer()],
          shuffle_questions?: boolean(),
          players: %{String.t() => player()},
          submissions: %{String.t() => submission()},
          asked: MapSet.t(String.t())
        }

  @enforce_keys [:room_code, :pack, :settings]
  defstruct [
    :room_code,
    :pack,
    :settings,
    game_number: 1,
    # Offset into the shuffled order for the current game.
    question_offset: 0,
    question_order: [],
    shuffle_questions?: true,
    mode: :cloud,
    phase: :lobby,
    question_index: nil,
    deadline: nil,
    paused_remaining_ms: nil,
    host_player_id: nil,
    players: %{},
    submissions: %{},
    # Who was in the room when the current question started. Only they can be
    # charged for not answering it — a late joiner never saw it (PROTOCOL.md §9).
    asked: MapSet.new()
  ]

  @doc "The compatibility boundary: clients sharing this major may play."
  @spec protocol_major() :: pos_integer()
  def protocol_major, do: @protocol_major

  @doc "Which revision of that major this server implements."
  @spec protocol_minor() :: non_neg_integer()
  def protocol_minor, do: @protocol_minor

  @spec new(String.t(), Pack.t(), keyword()) :: t()
  def new(room_code, %Pack{} = pack, opts \\ []) do
    %__MODULE__{
      room_code: room_code,
      pack: pack,
      mode: Keyword.get(opts, :mode, :cloud),
      settings: default_settings(pack),
      question_order:
        shuffled_order(
          question_indices(pack, default_settings(pack).difficulties),
          Keyword.get(opts, :shuffle_questions?, true)
        ),
      shuffle_questions?: Keyword.get(opts, :shuffle_questions?, true)
    }
  end

  @doc "Selects the quiz for a lobby, replacing any previous selection."
  @spec select_quiz(t(), Pack.t()) :: {:ok, t()} | error()
  def select_quiz(%__MODULE__{phase: :lobby} = game, %Pack{questions: questions} = pack)
      when questions != [] do
    {:ok,
     %{
       game
       | pack: pack,
         settings: default_settings(pack),
         question_offset: 0,
         question_order:
           shuffled_order(
             question_indices(pack, default_settings(pack).difficulties),
             game.shuffle_questions?
           )
     }}
  end

  def select_quiz(%__MODULE__{phase: :lobby}, _pack), do: {:error, :empty_pack}

  # Choosing what to play is a lobby-only thing; mid-game it is the phase that
  # is wrong, not the selection (PROTOCOL.md §4.2, §6.4).
  def select_quiz(_game, _pack), do: {:error, :invalid_phase}

  # Whole pack, at the first question's time limit (clamped to the allowed range).
  defp default_settings(pack) do
    time =
      case {pack.default_time_limit_ms, pack.questions} do
        {ms, _} when is_integer(ms) -> ms
        {nil, [first | _]} -> first.time_limit_ms
        {nil, []} -> @default_time_limit_ms
      end

    %{
      question_count: length(pack.questions),
      time_limit_ms: time |> max(@min_time_limit_ms) |> min(@max_time_limit_ms),
      difficulty_multiplier: pack.default_difficulty_multiplier,
      difficulties: difficulties(pack),
      available_difficulties: difficulties(pack)
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
    do: %{
      id: id,
      name: name,
      score: 0,
      connected: false,
      disconnected_at: nil,
      avatar_hue: avatar_hue
    }

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

  @spec set_connected(t(), String.t(), boolean(), integer()) :: t()
  def set_connected(game, id, connected?, now) do
    if player?(game, id) do
      update_in(game.players[id], fn player ->
        %{
          player
          | connected: connected?,
            # Kept from the first drop, not refreshed: a phone flapping between
            # two access points must not renew its own grace indefinitely.
            disconnected_at: if(connected?, do: nil, else: player.disconnected_at || now)
        }
      end)
    else
      game
    end
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
         {:ok, answer} <- validate_answer(payload["answer"]) do
      question = current_question(game)

      submission = %{
        answer: answer,
        auto_correct: Answer.correct?(answer, question.accepted_answers),
        override: nil,
        points: points(game, question)
      }

      answered = put_in(game.submissions[id], submission)

      {:ok, maybe_end_question(answered, now)}
    end
  end

  # A player who has been promoted (PROTOCOL.md §3.4) holds the role even though
  # their connection authenticated as a player, so host intents are theirs to
  # send. Checked before the catch-all below, which refuses everyone else.
  def handle(game, {:player, id}, intent, now) when id == :erlang.map_get(:host_player_id, game),
    do: handle(game, :host, intent, now)

  def handle(_game, {:player, _id}, _host_intent, _now), do: {:error, :not_host}
  def handle(%{host_player_id: nil}, :host, {:submit, _payload}, _now), do: {:error, :not_player}

  def handle(game, :host, {:submit, _payload} = intent, now),
    do: handle(game, {:player, game.host_player_id}, intent, now)

  def handle(game, :host, :next, now) do
    case game.phase do
      :lobby ->
        if game.pack.questions == [],
          do: {:error, :quiz_required},
          else: {:ok, start_question(game, 0, now)}

      :question ->
        {:ok, score_question(game)}

      :scoring ->
        {:ok, %{game | phase: :leaderboard}}

      :leaderboard ->
        {:ok, after_leaderboard(game, now)}

      :finished ->
        {:error, :invalid_phase}
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
      {:ok,
       %{
         game
         | settings: settings,
           question_offset: 0,
           question_order:
             shuffled_order(
               question_indices(game.pack, settings.difficulties),
               game.shuffle_questions?
             )
       }}
    end
  end

  def handle(game, :host, :rematch, _now) do
    with :ok <- require_phase(game, [:finished]) do
      players = Map.new(game.players, fn {id, player} -> {id, %{player | score: 0}} end)
      pack = empty_pack()

      {:ok,
       %{
         game
         | pack: pack,
           phase: :lobby,
           question_index: nil,
           deadline: nil,
           paused_remaining_ms: nil,
           submissions: %{},
           asked: MapSet.new(),
           players: players,
           game_number: game.game_number + 1,
           question_offset: 0,
           question_order: [],
           settings: default_settings(pack)
       }}
    end
  end

  def handle(game, :host, {:select_quiz, %Pack{} = pack}, _now),
    do: select_quiz(game, pack)

  # Handing the role over is allowed in any phase: a host who has to leave
  # mid-question should not have to end the game to do it (PROTOCOL.md §3.4).
  # The room shell owns tokens and connections, so it decides who is eligible;
  # this only moves the role within the game state.
  def handle(game, :host, {:transfer, payload}, _now) do
    with {:ok, id} <- validate_transfer(payload),
         :ok <- require_player(game, id) do
      {:ok, %{game | host_player_id: id}}
    end
  end

  def handle(_game, _actor, _intent, _now), do: {:error, :invalid_payload}

  @doc """
  Ends the current question if its deadline has passed, or if there is nobody
  left to wait for. Call before handling anything.
  """
  @spec tick(t(), integer()) :: t()
  def tick(%__MODULE__{phase: :question, deadline: deadline} = game, now)
      when is_integer(deadline) and now >= deadline,
      do: score_question(game)

  # Not only after a submission: the last person the room was waiting for may be
  # one whose grace has just run out, and nothing else would notice.
  def tick(%__MODULE__{phase: :question, paused_remaining_ms: nil} = game, now),
    do: maybe_end_question(game, now)

  def tick(game, _now), do: game

  @doc """
  The next time `tick/2` must run, if any: the question's own deadline, or a
  disconnected player's grace running out before it, whichever comes first.
  """
  @spec deadline(t()) :: integer() | nil
  def deadline(%__MODULE__{phase: :question, paused_remaining_ms: nil} = game) do
    case Enum.reject([game.deadline | grace_expiries(game)], &is_nil/1) do
      [] -> nil
      times -> Enum.min(times)
    end
  end

  def deadline(_game), do: nil

  ## Scoring

  @spec delta(submission()) :: integer()
  def delta(submission) do
    points = Map.get(submission, :points, @flat_points)
    if correct?(submission), do: points.right, else: points.wrong
  end

  @doc """
  What `question` is worth under the current settings: what a right answer earns and what
  a wrong one costs. Fixed per question when the player submits, so settings cannot move
  a score after the fact and an override recomputes with the same numbers.
  """
  @spec points(t(), Pack.Question.t()) :: points()
  def points(%__MODULE__{settings: %{difficulty_multiplier: true}}, question),
    do: Map.fetch!(@points, question.difficulty)

  def points(_game, _question), do: @flat_points

  @doc "What letting a question go by costs, whatever its difficulty."
  @spec skip_points() :: integer()
  def skip_points, do: @skip_points

  defp correct?(%{override: nil, auto_correct: auto}), do: auto
  defp correct?(%{override: override}), do: override

  defp start_question(game, index, now) do
    %{
      game
      | phase: :question,
        question_index: index,
        deadline: now + game.settings.time_limit_ms,
        paused_remaining_ms: nil,
        submissions: %{},
        asked: MapSet.new(Map.keys(game.players))
    }
  end

  # Nobody left to wait for: everyone the question was asked of has either
  # answered or been gone long enough that holding the room for them is only
  # making everybody else wait (PROTOCOL.md §6).
  #
  # At least one answer is required, so a room whose players have all wandered
  # off runs its clock down rather than racing through the pack unattended.
  defp maybe_end_question(%__MODULE__{phase: :question} = game, now) do
    if map_size(game.submissions) > 0 and
         Enum.all?(game.asked, &answered_or_gone?(game, &1, now)),
       do: score_question(game),
       else: game
  end

  defp maybe_end_question(game, _now), do: game

  defp answered_or_gone?(game, id, now),
    do: Map.has_key?(game.submissions, id) or gone?(game.players[id], now)

  # A screen that locked, or a tunnel, drops the socket for a few seconds while
  # the player is still very much there — so a disconnection is not immediately
  # taken as an answer nobody is coming. Someone who actually left stops
  # counting once the grace is up.
  defp gone?(nil, _now), do: true
  defp gone?(%{connected: true}, _now), do: false
  defp gone?(%{disconnected_at: nil}, _now), do: false
  defp gone?(%{disconnected_at: at}, now), do: now - at >= @waiting_grace_ms

  defp grace_expiries(game) do
    game.asked
    |> Enum.reject(&Map.has_key?(game.submissions, &1))
    |> Enum.flat_map(fn id ->
      case game.players[id] do
        %{connected: false, disconnected_at: at} when is_integer(at) ->
          [at + @waiting_grace_ms]

        _ ->
          []
      end
    end)
  end

  defp score_question(game) do
    players =
      Enum.reduce(Map.keys(game.players), game.players, fn id, players ->
        case question_delta(game, id) do
          nil -> players
          change -> update_in(players, [id, :score], &(&1 + change))
        end
      end)

    %{game | phase: :scoring, players: players, deadline: nil, paused_remaining_ms: nil}
  end

  # What this question did to `id`: their submission's delta, the skip penalty if they
  # were asked and said nothing, or nothing at all for someone who joined mid-question.
  defp question_delta(game, id) do
    case game.submissions[id] do
      nil -> if MapSet.member?(game.asked, id), do: @skip_points
      submission -> delta(submission)
    end
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

  defp validate_override(%{"player_id" => id, "correct" => correct})
       when is_binary(id) and is_boolean(correct),
       do: {:ok, id, correct}

  defp validate_override(_payload), do: {:error, :invalid_payload}

  defp validate_transfer(%{"player_id" => id}) when is_binary(id), do: {:ok, id}
  defp validate_transfer(_payload), do: {:error, :invalid_payload}

  defp validate_settings(game, %{
         "question_count" => count,
         "time_limit_ms" => time,
         "difficulty_multiplier" => bonus,
         "difficulties" => selected
       })
       when is_integer(count) and is_integer(time) and is_boolean(bonus) and is_list(selected) do
    selected = Enum.uniq(selected)
    eligible_count = max_question_count(game, selected)

    if valid_difficulties?(game, selected) and
         valid_question_count?(game, count, eligible_count, selected) and
         time in @min_time_limit_ms..@max_time_limit_ms,
       do:
         {:ok,
          %{
            question_count: min(count, eligible_count),
            time_limit_ms: time,
            difficulty_multiplier: bonus,
            difficulties: selected,
            available_difficulties: game.settings.available_difficulties
          }},
       else: {:error, :invalid_settings}
  end

  defp validate_settings(game, %{
         "question_count" => count,
         "time_limit_ms" => time,
         "difficulty_multiplier" => bonus
       })
       when is_integer(count) and is_integer(time) and is_boolean(bonus) do
    if count <= max_question_count(game) do
      validate_settings(game, %{
        "question_count" => count,
        "time_limit_ms" => time,
        "difficulty_multiplier" => bonus,
        "difficulties" => game.settings.difficulties
      })
    else
      {:error, :invalid_settings}
    end
  end

  defp validate_settings(_game, _payload), do: {:error, :invalid_settings}

  # Real difficulties, and ones the selected quizzes actually have: the host
  # cannot play a difficulty no question carries (PROTOCOL.md §5.1).
  defp valid_difficulties?(game, selected) do
    selected != [] and
      Enum.all?(
        selected,
        &(&1 in @difficulties and &1 in game.settings.available_difficulties)
      )
  end

  # Narrowing the difficulties shrinks the pool, so a count chosen before is
  # clamped rather than refused; asking for more than the *current* selection
  # holds is a mistake worth reporting (§6.2).
  defp valid_question_count?(game, count, eligible_count, selected) do
    count >= 1 and eligible_count >= 1 and
      (count <= eligible_count or selected != game.settings.difficulties)
  end

  defp max_question_count(game), do: max_question_count(game, game.settings.difficulties)

  defp max_question_count(game, difficulties),
    do: length(question_indices(game.pack, difficulties))

  defp empty_pack, do: %Pack{titles: [], questions: []}

  defp shuffled_order([], _shuffle?), do: []
  defp shuffled_order(indices, false), do: indices
  defp shuffled_order(indices, true), do: Enum.shuffle(indices)

  defp difficulties(pack) do
    @difficulties
    |> Enum.filter(fn difficulty ->
      Enum.any?(pack.questions, &(&1.difficulty == difficulty))
    end)
  end

  defp question_indices(pack, difficulties) do
    pack.questions
    |> Enum.with_index()
    |> Enum.filter(fn {question, _index} -> question.difficulty in difficulties end)
    |> Enum.map(fn {_question, index} -> index end)
  end

  ## Views (PROTOCOL.md §5.1, §7)

  @doc "The complete `RoomState` snapshot as seen by `recipient`."
  @spec view(t(), actor(), integer()) :: map()
  def view(game, recipient, now) do
    question = if game.phase in [:lobby, :finished], do: nil, else: current_question(game)
    # Same for every role: the host may be playing, so nobody gets an early look (§7).
    revealed? = game.phase in [:scoring, :leaderboard]

    %{
      protocol_version: @protocol_major,
      protocol_minor: @protocol_minor,
      room_code: game.room_code,
      mode: Atom.to_string(game.mode),
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
        max_question_count: max_question_count(game),
        difficulties: game.settings.difficulties,
        available_difficulties: game.settings.available_difficulties,
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
    order_index = rem(game.question_offset + game.question_index, length(game.question_order))
    index = Enum.at(game.question_order, order_index)
    %{Enum.at(game.pack.questions, index) | time_limit_ms: game.settings.time_limit_ms}
  end

  defp question_view(game, question) do
    points = points(game, question)

    question
    |> Map.take([:id, :type, :prompt, :image_url, :time_limit_ms, :difficulty])
    |> Map.put(:points, Map.put(points, :skipped, @skip_points))
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
        change = question_delta(game, player.id) do
      submission = game.submissions[player.id]

      %{
        player_id: player.id,
        answer: submission[:answer],
        auto_correct: submission[:auto_correct] || false,
        override: submission[:override],
        correct: submission != nil and correct?(submission),
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
          do: %{answer: nil, correct: false, delta: @skip_points}

      submission ->
        %{
          answer: submission.answer,
          correct: if(scored?, do: correct?(submission)),
          delta: if(scored?, do: delta(submission))
        }
    end
  end
end

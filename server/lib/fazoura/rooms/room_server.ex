defmodule Fazoura.Rooms.RoomServer do
  @moduledoc """
  Thin process shell around `Fazoura.Game` for one room.

  Owns the game state, supplies the clock, tracks connected channel processes (by
  monitoring them) and pushes a per-recipient `RoomState` to each after every change.
  Temporary: if it crashes, the room is gone and clients get `room_not_found`. Games do
  not survive a server restart (a v1 non-goal); `Fazoura.Rooms.Drain` at least makes the
  ending explicit.
  """

  use GenServer, restart: :temporary

  alias Fazoura.{Game, Quizzes}
  alias Fazoura.Game.Pack
  alias Fazoura.Rooms.Images

  # A room with nobody in it is over; the delay only exists so a lone host who
  # blips doesn't lose it, and so a new room has time for its first join
  # (PROTOCOL.md §3.4).
  @empty_ttl_ms :timer.seconds(30)

  # Most quizzes one round may draw from (PROTOCOL.md §6.4). A bound on how much
  # a single room can be made to hold, inline photos included.
  @max_quizzes 10
  @finished_ttl_ms :timer.minutes(10)
  @token_max_age_s 86_400

  def start_link(opts) do
    code = Keyword.fetch!(opts, :code)
    GenServer.start_link(__MODULE__, opts, name: {:via, Registry, {Fazoura.Rooms.Registry, code}})
  end

  @doc """
  The host token for generation `generation` of `code`.

  The generation is what makes a transfer stick: it increments on every change of
  host, so a token minted for an earlier holder no longer verifies and a demoted
  host cannot rejoin as host (§3.3).
  """
  @spec host_token(String.t(), non_neg_integer()) :: String.t()
  def host_token(code, generation \\ 0),
    do: Phoenix.Token.sign(FazouraWeb.Endpoint, "host", {code, generation})

  ## Callbacks

  @impl true
  def init(opts) do
    now = Keyword.get(opts, :now, fn -> System.os_time(:millisecond) end)
    code = Keyword.fetch!(opts, :code)

    game =
      Game.new(code, Keyword.fetch!(opts, :pack),
        mode: Keyword.get(opts, :mode, :cloud),
        shuffle_questions?: Keyword.get(opts, :shuffle_questions?, true)
      )

    state = %{
      game: game,
      now: now,
      conns: %{},
      # Which host_token is currently valid; bumped on every change of host.
      generation: 0,
      # Whether the connection that authenticated with the host token is still
      # the holder. False once the role has moved to a player (PROTOCOL.md §3.4);
      # `demoted_player_id` is then the player that connection still plays as,
      # or nil if the host was never playing.
      held_by_host_conn?: true,
      demoted_player_id: nil,
      # Players owed a fresh host_token in their next snapshot, by player id (or
      # `:host` for a host who isn't playing). Cleared once delivered.
      pending_tokens: %{},
      empty_since: now.(),
      finished_at: nil,
      timer: nil
    }

    {:ok, schedule(state)}
  end

  @impl true
  def handle_call({:join, pid, params}, _from, state) do
    case authenticate(state.game, state.generation, params) do
      {:ok, actor, reply, game} ->
        state = state |> put_game(game) |> add_conn(pid, actor) |> broadcast() |> schedule()
        {:reply, {:ok, reply, self()}, state}

      {:error, _code} = error ->
        {:reply, error, state}
    end
  end

  def handle_call({:intent, pid, intent}, _from, state) do
    case Map.fetch(state.conns, pid) do
      {:ok, actor} -> handle_intent(state, actor, intent)
      :error -> {:reply, {:error, :invalid_token}, state}
    end
  end

  # Read-only snapshot for the admin dashboard (Fazoura.Rooms.active/0).
  def handle_call(:summary, _from, state) do
    game = state.game

    summary = %{
      code: game.room_code,
      phase: game.phase,
      quiz_title: Enum.join(game.pack.titles, " + "),
      players: map_size(game.players),
      connections: map_size(state.conns),
      answered: map_size(game.submissions),
      question_number: game.question_index && game.question_index + 1,
      question_count: game.settings.question_count,
      game_number: game.game_number,
      host_present: Enum.any?(Map.values(state.conns), &(&1 == :host))
    }

    {:reply, summary, state}
  end

  # Read-only: does this device's host token still open this room?
  #
  # A room can be gone long before the token that opened it expires — empty for
  # 30 s, or the host demoted the moment anybody else was connected — so the
  # home screen asks before offering to take it back (PROTOCOL.md §3.3).
  #
  # A caller without the current token is told the room does not exist rather
  # than that their token is wrong, so this cannot be used to find live rooms by
  # guessing codes, and a demoted host cannot use it to confirm the room is
  # still running.
  def handle_call({:status, host_token}, _from, state) do
    reply =
      if current_host_token?(state, host_token) do
        {:ok,
         %{
           room_code: state.game.room_code,
           phase: Atom.to_string(state.game.phase),
           players: map_size(state.game.players)
         }}
      else
        {:error, :room_not_found}
      end

    {:reply, reply, state}
  end

  def handle_call(:tick, _from, state) do
    case advance(state) do
      {:ok, state} -> {:reply, :ok, state}
      {:close, reason, state} -> close(state, reason, {:reply, :ok})
    end
  end

  @impl true
  def handle_info(:tick, state) do
    case advance(state) do
      {:ok, state} -> {:noreply, state}
      {:close, reason, state} -> close(state, reason, :noreply)
    end
  end

  # The server is going down (deploy, restart). Say so while the sockets are still
  # open, so clients show "the party ended" instead of a silent reconnect loop.
  def handle_info(:shutdown, state), do: close(state, :shutdown, :noreply)

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    case Map.pop(state.conns, pid) do
      {nil, _conns} -> {:noreply, state}
      {actor, conns} -> {:noreply, remove_conn(%{state | conns: conns}, actor)}
    end
  end

  # The host connection that handed the role away keeps its socket, its player id
  # and its score, but loses its powers — so it acts as that player from now on,
  # and host intents get `not_host` like anyone else's (PROTOCOL.md §3.4).
  # The same test `authenticate/3` makes, without joining anything: the token has
  # to verify, name this room, and belong to the generation currently in force.
  defp current_host_token?(state, token) when is_binary(token) do
    case Phoenix.Token.verify(FazouraWeb.Endpoint, "host", token, max_age: @token_max_age_s) do
      {:ok, {code, generation}} ->
        code == state.game.room_code and generation == state.generation

      _ ->
        false
    end
  end

  defp current_host_token?(_state, _token), do: false

  defp handle_intent(%{held_by_host_conn?: false} = state, :host, intent) do
    case state.demoted_player_id do
      nil -> {:reply, {:error, :not_host}, state}
      id -> handle_intent(state, {:player, id}, intent)
    end
  end

  defp handle_intent(state, :host, {:select_quiz, payload}),
    do: select_quiz_intent(state, payload)

  defp handle_intent(state, {:player, id}, {:select_quiz, payload})
       when id == state.game.host_player_id,
       do: select_quiz_intent(state, payload)

  # Ending the room is the shell's business, not the game's: there is no state
  # to advance, only sockets to tell (PROTOCOL.md §3.4).
  defp handle_intent(state, :host, :close),
    do: close(state, :closed, {:reply, :ok})

  defp handle_intent(state, {:player, _id}, :close),
    do: {:reply, {:error, :not_host}, state}

  # Transfer needs both halves: the game moves the role, the shell mints the new
  # token. It also needs the connection list, which the game does not have.
  defp handle_intent(state, :host, {:transfer, payload} = intent) do
    with {:ok, id} <- fetch_player_id(payload),
         :ok <- require_connected(state, id),
         # Validates the move; grant_host is what actually applies it, so that it
         # can see who the outgoing host was before the state changes.
         {:ok, _game} <- Game.handle(state.game, :host, intent, state.now.()) do
      state = state |> grant_host(id) |> broadcast() |> schedule()
      {:reply, :ok, state}
    else
      {:error, _code} = error -> {:reply, error, state}
    end
  end

  defp handle_intent(state, actor, intent) do
    now = state.now.()
    ticked = Game.tick(state.game, now)

    case Game.handle(ticked, actor, intent, now) do
      {:ok, game} -> {:reply, :ok, update_game(state, game)}
      {:error, _code} = error -> {:reply, error, update_game(state, ticked)}
    end
  end

  defp select_quiz_intent(state, payload) do
    with {:ok, pack, image_keys} <- resolve_selection(payload),
         {:ok, game} <- Game.handle(state.game, :host, {:select_quiz, pack}, state.now.()) do
      :ok = Images.attach(image_keys, self())
      {:reply, :ok, update_game(state, game)}
    else
      {:error, _code} = error -> {:reply, error, state}
    end
  end

  # The whole selection, resolved into the one pool the round is played from
  # (PROTOCOL.md §6.4). Entries may mix stored quizzes with inline documents.
  #
  # Inline photos go into memory as each quiz resolves, so the accumulator also
  # carries the keys and the bytes spent so far: the keys because a selection
  # that fails half way must not leave photos behind that no room will ever
  # collect, and the bytes because `max_inline_bytes/0` bounds the room rather
  # than each quiz in it.
  defp resolve_selection(%{"quizzes" => quizzes})
       when is_list(quizzes) and quizzes != [] and length(quizzes) <= @max_quizzes do
    quizzes
    |> Enum.reduce_while({:ok, [], [], 0}, fn entry, {:ok, packs, keys, spent} ->
      case resolve_quiz(entry, spent) do
        {:ok, pack, image_keys, spent} ->
          {:cont, {:ok, [pack | packs], keys ++ image_keys, spent}}

        error ->
          {:halt, {error, keys}}
      end
    end)
    |> case do
      {:ok, packs, image_keys, _spent} ->
        {:ok, Pack.merge(Enum.reverse(packs)), image_keys}

      {error, orphans} ->
        Images.delete(orphans)
        error
    end
  end

  defp resolve_selection(_payload), do: {:error, :invalid_quiz}

  defp resolve_quiz(%{"quiz_id" => id}, spent) when is_binary(id) do
    case Quizzes.fetch(id) do
      # A stored quiz's photos are on disk and served from there, so they cost
      # the room nothing to hold.
      {:ok, quiz} -> {:ok, Quizzes.to_pack(quiz), [], spent}
      _ -> {:error, :quiz_not_found}
    end
  end

  defp resolve_quiz(%{"quiz" => %{} = document}, spent) do
    case Quizzes.inline_pack(document, spent) do
      {:ok, pack, image_keys, spent} -> {:ok, pack, image_keys, spent}
      _ -> {:error, :invalid_quiz}
    end
  end

  defp resolve_quiz(_entry, _spent), do: {:error, :invalid_quiz}

  defp fetch_player_id(%{"player_id" => id}) when is_binary(id), do: {:ok, id}
  defp fetch_player_id(_payload), do: {:error, :invalid_payload}

  # Handing the role to someone who has left would leave the room hostless, which
  # is the very thing promotion exists to prevent.
  defp require_connected(state, id) do
    if id in connected_player_ids(state), do: :ok, else: {:error, :not_connected}
  end

  ## Connections

  defp authenticate(game, generation, %{"host_token" => token} = params)
       when is_binary(token) do
    case Phoenix.Token.verify(FazouraWeb.Endpoint, "host", token, max_age: @token_max_age_s) do
      # Only the current generation: a token from before a transfer is as good
      # as forged, or a demoted host could take the room back (§3.3).
      {:ok, {code, ^generation}} when code == game.room_code ->
        with {:ok, game} <- maybe_add_host_player(game, params["display_name"]) do
          {:ok, :host, %{role: "host", player_id: game.host_player_id, player_token: nil}, game}
        end

      _ ->
        {:error, :invalid_token}
    end
  end

  defp authenticate(game, _generation, %{"player_token" => token}) when is_binary(token) do
    case Phoenix.Token.verify(FazouraWeb.Endpoint, "player", token, max_age: @token_max_age_s) do
      {:ok, {code, id}} when code == game.room_code ->
        if Game.player?(game, id),
          do: {:ok, {:player, id}, player_reply(id, token), game},
          else: {:error, :invalid_token}

      _ ->
        {:error, :invalid_token}
    end
  end

  defp authenticate(game, _generation, params) do
    id = new_player_id()

    hue = Game.pick_avatar_hue(game)

    with {:ok, game} <- Game.add_player(game, id, params["display_name"], hue) do
      token = Phoenix.Token.sign(FazouraWeb.Endpoint, "player", {game.room_code, id})
      {:ok, {:player, id}, player_reply(id, token), game}
    end
  end

  # A host join with a display name makes the host play too (PROTOCOL.md §4.1).
  defp maybe_add_host_player(game, nil), do: {:ok, game}

  defp maybe_add_host_player(game, name),
    do: Game.add_host_player(game, new_player_id(), name, Game.pick_avatar_hue(game))

  defp new_player_id, do: "p_" <> Base.url_encode64(:crypto.strong_rand_bytes(6), padding: false)

  defp player_reply(id, token), do: %{role: "player", player_id: id, player_token: token}

  defp add_conn(state, pid, actor) do
    Process.monitor(pid)
    state = %{state | conns: Map.put(state.conns, pid, actor), empty_since: nil}

    case actor do
      :host ->
        %{state | game: set_host_connected(state.game, true, state.now.())}

      {:player, id} ->
        %{state | game: Game.set_connected(state.game, id, true, state.now.())}
    end
  end

  defp set_host_connected(game, connected?, now),
    do: Game.set_connected(game, game.host_player_id, connected?, now)

  defp remove_conn(state, actor) do
    # Another socket may still be acting as the same player, in which case
    # nothing has really left.
    if actor in Map.values(state.conns) do
      state
    else
      state
      |> mark_disconnected(actor)
      |> maybe_promote(actor)
      |> mark_empty_if_deserted()
      |> broadcast()
      |> schedule()
    end
  end

  defp maybe_promote(state, :host), do: promote_host(state)
  defp maybe_promote(state, {:player, _id}), do: state

  defp mark_disconnected(state, :host),
    do: put_game(state, set_host_connected(state.game, false, state.now.()))

  defp mark_disconnected(state, {:player, id}),
    do: put_game(state, Game.set_connected(state.game, id, false, state.now.()))

  # The host's connection is gone: rather than leave the room hostless until it
  # times out, hand the role to someone who is still here (PROTOCOL.md §3.4).
  # Random, because there is no better signal — the previous host chose not to
  # pick one, or could not.
  defp promote_host(state) do
    case connected_player_ids(state) do
      [] -> state
      ids -> grant_host(state, Enum.random(ids))
    end
  end

  # Moves the role to `player_id` and mints them a token. The generation bump is
  # what retires every token issued before this point.
  defp grant_host(state, player_id) do
    generation = state.generation + 1

    %{
      state
      | game: %{state.game | host_player_id: player_id},
        generation: generation,
        held_by_host_conn?: false,
        demoted_player_id: state.demoted_player_id || state.game.host_player_id,
        pending_tokens:
          Map.put(state.pending_tokens, player_id, host_token(state.game.room_code, generation))
    }
  end

  defp connected_player_ids(state) do
    for {_pid, {:player, id}} <- state.conns, uniq: true, do: id
  end

  defp mark_empty_if_deserted(state) do
    if state.conns == %{},
      do: %{state | empty_since: state.now.()},
      else: state
  end

  ## State changes

  defp put_game(state, game), do: %{state | game: game}

  defp update_game(%{game: game} = state, game), do: state

  defp update_game(state, game) do
    # A rematch leaves `finished`, which cancels the finished-room expiry.
    finished_at =
      cond do
        game.phase != :finished -> nil
        is_nil(state.finished_at) -> state.now.()
        true -> state.finished_at
      end

    %{state | game: game, finished_at: finished_at} |> broadcast() |> schedule()
  end

  defp broadcast(state) do
    now = state.now.()

    for {pid, actor} <- state.conns do
      view =
        state.game
        |> Game.view(recipient(state, actor), now)
        |> put_host_token(state, actor)

      send(pid, {:room_state, view})
    end

    # Delivered once: the token is only news to the client that just received it.
    %{state | pending_tokens: %{}}
  end

  # A connection that authenticated as host may no longer hold the role: after a
  # transfer it is an ordinary client, and must be told so (PROTOCOL.md §3.4).
  # `held_by_host_conn?` is the room's record of whether the host connection is
  # still the holder, which the game state cannot express on its own.
  defp recipient(%{held_by_host_conn?: true}, :host), do: {:host, true}
  defp recipient(%{demoted_player_id: nil}, :host), do: {:host, false}
  defp recipient(%{demoted_player_id: id}, :host), do: {:player, id}
  defp recipient(_state, {:player, _id} = actor), do: actor

  # A new host_token reaches exactly one recipient — the player who now holds the
  # role — and only in the snapshot right after they got it (PROTOCOL.md §5.1).
  defp put_host_token(view, state, {:player, id}) do
    put_in(view, [:you, :host_token], Map.get(state.pending_tokens, id))
  end

  defp put_host_token(view, _state, :host), do: put_in(view, [:you, :host_token], nil)

  ## Timers

  defp advance(state) do
    now = state.now.()
    state = update_game(state, Game.tick(state.game, now))

    cond do
      expired?(state.empty_since, @empty_ttl_ms, now) -> {:close, :empty, state}
      expired?(state.finished_at, @finished_ttl_ms, now) -> {:close, :finished, state}
      true -> {:ok, schedule(state)}
    end
  end

  defp expired?(nil, _ttl, _now), do: false
  defp expired?(since, ttl, now), do: now - since >= ttl

  defp schedule(state) do
    if state.timer, do: Process.cancel_timer(state.timer)

    due =
      [
        Game.deadline(state.game),
        state.empty_since && state.empty_since + @empty_ttl_ms,
        state.finished_at && state.finished_at + @finished_ttl_ms
      ]
      |> Enum.reject(&is_nil/1)

    timer =
      case due do
        [] -> nil
        _ -> Process.send_after(self(), :tick, max(Enum.min(due) - state.now.(), 0))
      end

    %{state | timer: timer}
  end

  defp close(state, reason, reply) do
    for {pid, _actor} <- state.conns, do: send(pid, {:room_closed, reason})

    case reply do
      {:reply, value} -> {:stop, :normal, value, state}
      :noreply -> {:stop, :normal, state}
    end
  end
end

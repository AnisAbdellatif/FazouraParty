defmodule Fazoura.Rooms.RoomServer do
  @moduledoc """
  Thin process shell around `Fazoura.Game` for one room.

  Owns the game state, supplies the clock, tracks connected channel processes (by
  monitoring them) and pushes a per-recipient `RoomState` to each after every change —
  coalesced, so changes that arrive together go out as one snapshot (PROTOCOL.md §5.1).
  Temporary: if it crashes, the room is gone and clients get `room_not_found`. Games do
  not survive a server restart (a v1 non-goal); `Fazoura.Rooms.Drain` at least makes the
  ending explicit.
  """

  use GenServer, restart: :temporary

  alias Fazoura.Game
  alias Fazoura.Game.{Pack, View}
  alias Fazoura.Rooms.{Images, Listing, Selection, Tokens}

  # A room with nobody in it is over; the delay only exists so a lone host who
  # blips doesn't lose it, and so a new room has time for its first join
  # (PROTOCOL.md §3.4).
  @empty_ttl_ms :timer.seconds(30)
  @finished_ttl_ms :timer.minutes(10)

  # The shortest gap between two broadcasts. A broadcast is one snapshot per
  # recipient, each the size of the whole room, so it costs the square of the
  # player count, and every answer used to trigger one: 100 players answering at
  # once was 100 × 101 snapshots. A change after a quiet spell still goes out at
  # once; changes within the gap ride on the next one (PROTOCOL.md §5.1).
  @broadcast_interval_ms 100

  def start_link(opts) do
    code = Keyword.fetch!(opts, :code)
    GenServer.start_link(__MODULE__, opts, name: {:via, Registry, {Fazoura.Rooms.Registry, code}})
  end

  @doc "This module's part of `protocol/fixtures/constants.json` (see `Fazoura.Game.constants/0`)."
  @spec constants() :: %{String.t() => term()}
  def constants do
    %{
      "empty_room_ttl_ms" => @empty_ttl_ms,
      "finished_room_ttl_ms" => @finished_ttl_ms,
      "broadcast_interval_ms" => @broadcast_interval_ms
    }
  end

  ## Callbacks

  @impl true
  def init(opts) do
    now = Keyword.get(opts, :now, fn -> System.os_time(:millisecond) end)
    code = Keyword.fetch!(opts, :code)

    interval =
      Keyword.get_lazy(opts, :broadcast_interval_ms, fn ->
        Application.get_env(:fazoura, :broadcast_interval_ms, @broadcast_interval_ms)
      end)

    game =
      Game.new(code, Keyword.fetch!(opts, :pack),
        mode: Keyword.get(opts, :mode, :cloud),
        listed: Keyword.get(opts, :listed, false),
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
      # What moderation needs to know about who is here, by player id (or `:host`
      # for a host who isn't playing): the keyed hash of their address, and whether
      # it was banned from public rooms when they joined. Never broadcast; a report
      # takes the hash, and a room that goes public keeps banned hosts out.
      ip_hashes: %{},
      banned: MapSet.new(),
      # The room size codes this room has taken, by id, so the same one twice counts once.
      size_codes: %{},
      empty_since: now.(),
      finished_at: nil,
      timer: nil,
      # Snapshot pacing. `flush` is set while a broadcast is on its way — queued
      # behind whatever is already in the mailbox, or waiting out the interval —
      # and every change until it goes out rides on it. Measured on the monotonic
      # clock, not `now`: this is delivery, not game time, and a test's frozen
      # game clock must not hold snapshots back.
      broadcast_interval_ms: interval,
      flush: nil,
      last_broadcast_at: nil
    }

    {:ok, state |> publish_listing() |> schedule()}
  end

  @impl true
  def handle_call({:join, pid, params, meta}, _from, state) do
    with :ok <- admit(state.game, meta),
         {:ok, actor, reply, game} <- authenticate(state.game, state.generation, params) do
      state =
        state
        |> put_game(game)
        |> remember(actor, meta)
        |> add_conn(pid, actor)
        |> broadcast()
        |> publish_listing()
        |> schedule()

      {:reply, {:ok, reply, self()}, state}
    else
      {:error, _code} = error -> {:reply, error, state}
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
  # Which stored quiz a question in this room came from (QUIZ_FORMAT.md §5.9).
  #
  # The id is answered to somebody already in the room and never broadcast: a
  # quiz id in a `state` would let any player fetch the accepted answers from
  # `GET /api/quizzes/:id/download` mid-game.
  def handle_call({:source_quiz, question_id, token}, _from, state) do
    {:reply, source_quiz(state, question_id, token), state}
  end

  # What a report about a player keeps (PROTOCOL.md §3.5): what was on the screen,
  # and the hash a ban can act on. Asked by somebody in the room, like `source_quiz`.
  def handle_call({:player_report, player_id, token}, _from, state) do
    reply =
      with :ok <- verify_member(state, token),
           %{name: name} <- state.game.players[player_id] || {:error, :unknown_player} do
        submission = state.game.submissions[player_id]

        {:ok,
         %{
           room_code: state.game.room_code,
           player_name: name,
           answer: submission && submission.answer,
           ip_hash: state.ip_hashes[player_id]
         }}
      end

    {:reply, reply, state}
  end

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

  def handle_info(:flush, state), do: {:noreply, push_snapshots(%{state | flush: nil})}

  # The server is going down (deploy, restart). Say so while the sockets are still
  # open, so clients show "the party ended" instead of a silent reconnect loop.
  def handle_info(:shutdown, state), do: close(state, :shutdown, :noreply)

  # An admin answering a report about somebody in this room (ADMIN.md §3.3).
  def handle_info(:admin_close, state), do: close(state, :closed, :noreply)

  def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
    case Map.pop(state.conns, pid) do
      {nil, _conns} -> {:noreply, state}
      {actor, conns} -> {:noreply, remove_conn(%{state | conns: conns}, actor)}
    end
  end

  defp source_quiz(state, question_id, token) do
    with :ok <- verify_member(state, token),
         {:ok, quiz_id} <- Pack.source_quiz(state.game.pack, question_id) do
      # An inline quiz was never published, so there is nothing anybody could
      # take down. Saying so is more use than accepting the report into a void.
      if quiz_id, do: {:ok, quiz_id}, else: {:error, :quiz_not_public}
    end
  end

  # Proof that the caller is in this room, by either token a join issues
  # (PROTOCOL.md §3.3). Without it this would answer differently for a real room
  # code than for a made-up one, and become the room-code oracle that §3.1 goes
  # out of its way not to be. A wrong token is `room_not_found` for the same
  # reason `GET /api/rooms/:code` gives that answer to everything.
  defp verify_member(state, token) do
    if current_host_token?(state, token) or current_player_token?(state, token),
      do: :ok,
      else: {:error, :room_not_found}
  end

  defp current_player_token?(state, token) do
    case Tokens.player_id(token, state.game.room_code) do
      {:ok, id} -> Game.player?(state.game, id)
      :error -> false
    end
  end

  # The same test `authenticate/3` makes, without joining anything: the token has
  # to verify, name this room, and belong to the generation currently in force.
  defp current_host_token?(state, token),
    do: Tokens.host?(token, state.game.room_code, state.generation)

  # The host connection that handed the role away keeps its socket, its player id
  # and its score, but loses its powers — so it acts as that player from now on,
  # and host intents get `not_host` like anyone else's (PROTOCOL.md §3.4).
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

  # Removing needs the shell too: the game forgets the player, the shell tells their
  # connections so and lets go of them (PROTOCOL.md §4.2).
  defp handle_intent(state, :host, {:remove_player, _payload} = intent) do
    case Game.handle(state.game, :host, intent, state.now.()) do
      {:ok, game} ->
        removed = Enum.find(Map.keys(state.game.players), &(not Map.has_key?(game.players, &1)))
        {:reply, :ok, state |> let_go(removed) |> update_game(game)}

      {:error, _code} = error ->
        {:reply, error, state}
    end
  end

  # A room going public keeps a banned host out, as joining one would (§3.5).
  defp handle_intent(state, :host, {:set_listed, %{"listed" => true}} = intent) do
    if MapSet.member?(state.banned, holder_key(state)),
      do: {:reply, {:error, :banned}, state},
      else: game_intent(state, :host, intent)
  end

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

  # Before the channel counts a use of a room size code (PROTOCOL.md §6.5): may this
  # connection unlock the room, and has the room had this code before, which costs no
  # second use.
  defp handle_intent(state, actor, {:check_size_code, %{id: id}}) do
    case Game.check_unlock(state.game, actor) do
      :ok when is_map_key(state.size_codes, id) -> {:reply, :already, state}
      :ok -> {:reply, :new, state}
      {:error, _code} = error -> {:reply, error, state}
    end
  end

  # A room size code the channel has counted. Checked again, since the room may have
  # changed between the two calls; the channel gives the use back on anything but `:ok`.
  defp handle_intent(state, actor, {:redeem_size_code, %{id: id, room_size: size}}) do
    case Game.handle(state.game, actor, {:unlock_room_size, size}, state.now.()) do
      {:ok, _game} when is_map_key(state.size_codes, id) ->
        {:reply, :already, state}

      {:ok, game} ->
        state = %{state | size_codes: Map.put(state.size_codes, id, true)}
        {:reply, :ok, update_game(state, game)}

      {:error, _code} = error ->
        {:reply, error, state}
    end
  end

  defp handle_intent(state, actor, intent), do: game_intent(state, actor, intent)

  defp game_intent(state, actor, intent) do
    now = state.now.()
    ticked = Game.tick(state.game, now)

    case Game.handle(ticked, actor, intent, now) do
      {:ok, game} -> {:reply, :ok, update_game(state, game)}
      {:error, _code} = error -> {:reply, error, update_game(state, ticked)}
    end
  end

  defp select_quiz_intent(state, payload) do
    case Selection.resolve(state.game, payload) do
      {:ok, pack, image_keys} -> apply_selection(state, pack, image_keys)
      {:error, _code} = error -> {:reply, error, state}
    end
  end

  defp apply_selection(state, pack, image_keys) do
    case Game.handle(state.game, :host, {:select_quiz, pack}, state.now.()) do
      {:ok, game} ->
        :ok = Images.attach(image_keys, self())
        {:reply, :ok, update_game(state, game)}

      # Nothing is holding these photos: without this they would sit in memory
      # until the node restarts.
      {:error, _code} = error ->
        Images.delete(image_keys)
        {:reply, error, state}
    end
  end

  defp fetch_player_id(%{"player_id" => id}) when is_binary(id), do: {:ok, id}
  defp fetch_player_id(_payload), do: {:error, :invalid_payload}

  # Handing the role to someone who has left would leave the room hostless, which
  # is the very thing promotion exists to prevent.
  defp require_connected(state, id) do
    if id in connected_player_ids(state), do: :ok, else: {:error, :not_connected}
  end

  ## Connections

  # A public room keeps banned connections out (PROTOCOL.md §3.5). The ban was looked
  # up by the channel, so the room never touches the database during play.
  defp admit(%Game{listed: true}, %{banned?: true}), do: {:error, :banned}
  defp admit(_game, _meta), do: :ok

  defp remember(state, actor, meta) do
    key = actor_key(state.game, actor)

    %{
      state
      | ip_hashes: Map.put(state.ip_hashes, key, meta[:ip_hash]),
        banned: if(meta[:banned?], do: MapSet.put(state.banned, key), else: state.banned)
    }
  end

  # Moderation's name for whoever is behind a connection: their player id, or
  # `:host` for a host who isn't playing.
  defp actor_key(game, :host), do: game.host_player_id || :host
  defp actor_key(_game, {:player, id}), do: id

  defp holder_key(%{held_by_host_conn?: true} = state), do: actor_key(state.game, :host)
  defp holder_key(state), do: state.game.host_player_id

  # Tells a removed player's connections they are out, and stops counting them. A
  # demoted host still playing is one of those connections.
  defp let_go(state, player_id) do
    gone =
      for {pid, actor} <- state.conns,
          actor == {:player, player_id} or
            (actor == :host and not state.held_by_host_conn? and
               state.demoted_player_id == player_id),
          do: pid

    for pid <- gone, do: send(pid, {:room_closed, :removed})

    %{
      state
      | conns: Map.drop(state.conns, gone),
        demoted_player_id:
          if(state.demoted_player_id == player_id, do: nil, else: state.demoted_player_id)
    }
    |> mark_empty_if_deserted()
  end

  defp authenticate(game, generation, %{"host_token" => token} = params)
       when is_binary(token) do
    # Only the current generation: a token from before a transfer is as good as
    # forged, or a demoted host could take the room back (§3.3).
    if Tokens.host?(token, game.room_code, generation) do
      with {:ok, game} <- maybe_add_host_player(game, params["display_name"]) do
        {:ok, :host, %{role: "host", player_id: game.host_player_id, player_token: nil}, game}
      end
    else
      {:error, :invalid_token}
    end
  end

  defp authenticate(game, _generation, %{"player_token" => token}) when is_binary(token) do
    with {:ok, id} <- Tokens.player_id(token, game.room_code),
         true <- Game.player?(game, id) do
      {:ok, {:player, id}, player_reply(id, token), game}
    else
      _ -> {:error, :invalid_token}
    end
  end

  defp authenticate(game, _generation, params) do
    id = new_player_id()

    hue = Game.pick_avatar_hue(game)

    with {:ok, game} <- Game.add_player(game, id, params["display_name"], hue) do
      token = Tokens.player_token(game.room_code, id)
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
          Map.put(
            state.pending_tokens,
            player_id,
            Tokens.host_token(state.game.room_code, generation)
          )
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

    %{state | game: game, finished_at: finished_at}
    |> broadcast()
    |> publish_listing()
    |> schedule()
  end

  defp publish_listing(state) do
    :ok = Listing.publish(state.game)
    state
  end

  # Asks for a broadcast rather than making one. It is sent as a message to this
  # process, so everything already queued — a burst of answers — is applied first
  # and goes out in the same snapshot; and no sooner than the interval after the
  # last one, so a room under load sends at most a few a second whatever arrives.
  # The snapshot is built when it is sent, from the state as it is then.
  defp broadcast(%{flush: nil} = state) do
    wait =
      case state.last_broadcast_at do
        nil -> 0
        at -> at + state.broadcast_interval_ms - System.monotonic_time(:millisecond)
      end

    flush =
      if wait > 0,
        do: Process.send_after(self(), :flush, wait),
        else: send(self(), :flush)

    %{state | flush: flush}
  end

  defp broadcast(state), do: state

  defp push_snapshots(state) do
    now = state.now.()

    for {pid, actor} <- state.conns do
      view =
        state.game
        |> View.room_state(recipient(state, actor), now)
        |> put_host_token(state, actor)

      send(pid, {:room_state, view})
    end

    # Delivered once: the token is only news to the client that just received it.
    %{state | pending_tokens: %{}, last_broadcast_at: System.monotonic_time(:millisecond)}
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

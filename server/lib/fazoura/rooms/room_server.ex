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

  alias Fazoura.Game

  @host_timeout_ms :timer.minutes(10)
  @finished_ttl_ms :timer.minutes(10)
  @token_max_age_s 86_400

  def start_link(opts) do
    code = Keyword.fetch!(opts, :code)
    GenServer.start_link(__MODULE__, opts, name: {:via, Registry, {Fazoura.Rooms.Registry, code}})
  end

  @spec host_token(String.t()) :: String.t()
  def host_token(code), do: Phoenix.Token.sign(FazouraWeb.Endpoint, "host", code)

  ## Callbacks

  @impl true
  def init(opts) do
    now = Keyword.get(opts, :now, fn -> System.os_time(:millisecond) end)
    code = Keyword.fetch!(opts, :code)
    game = Game.new(code, Keyword.fetch!(opts, :pack), mode: Keyword.get(opts, :mode, :cloud))

    state = %{
      game: game,
      now: now,
      conns: %{},
      host_absent_since: now.(),
      finished_at: nil,
      timer: nil
    }

    {:ok, schedule(state)}
  end

  @impl true
  def handle_call({:join, pid, params}, _from, state) do
    case authenticate(state.game, params) do
      {:ok, actor, reply, game} ->
        state = state |> put_game(game) |> add_conn(pid, actor) |> broadcast() |> schedule()
        {:reply, {:ok, reply, self()}, state}

      {:error, _code} = error ->
        {:reply, error, state}
    end
  end

  def handle_call({:intent, pid, intent}, _from, state) do
    case Map.fetch(state.conns, pid) do
      {:ok, actor} ->
        now = state.now.()
        ticked = Game.tick(state.game, now)

        case Game.handle(ticked, actor, intent, now) do
          {:ok, game} -> {:reply, :ok, update_game(state, game)}
          {:error, _code} = error -> {:reply, error, update_game(state, ticked)}
        end

      :error ->
        {:reply, {:error, :invalid_token}, state}
    end
  end

  # Read-only snapshot for the admin dashboard (Fazoura.Rooms.active/0).
  def handle_call(:summary, _from, state) do
    game = state.game

    summary = %{
      code: game.room_code,
      phase: game.phase,
      quiz_title: game.pack.title,
      players: map_size(game.players),
      connections: map_size(state.conns),
      answered: map_size(game.submissions),
      question_number: game.question_index && game.question_index + 1,
      question_count: game.settings.question_count,
      game_number: game.game_number,
      host_present: state.host_absent_since == nil
    }

    {:reply, summary, state}
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

  ## Connections

  defp authenticate(game, %{"host_token" => token} = params) when is_binary(token) do
    case Phoenix.Token.verify(FazouraWeb.Endpoint, "host", token, max_age: @token_max_age_s) do
      {:ok, code} when code == game.room_code ->
        with {:ok, game} <- maybe_add_host_player(game, params["display_name"]) do
          {:ok, :host, %{role: "host", player_id: game.host_player_id, player_token: nil}, game}
        end

      _ ->
        {:error, :invalid_token}
    end
  end

  defp authenticate(game, %{"player_token" => token}) when is_binary(token) do
    case Phoenix.Token.verify(FazouraWeb.Endpoint, "player", token, max_age: @token_max_age_s) do
      {:ok, {code, id}} when code == game.room_code ->
        if Game.player?(game, id),
          do: {:ok, {:player, id}, player_reply(id, token), game},
          else: {:error, :invalid_token}

      _ ->
        {:error, :invalid_token}
    end
  end

  defp authenticate(game, params) do
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
    state = %{state | conns: Map.put(state.conns, pid, actor)}

    case actor do
      :host ->
        %{state | host_absent_since: nil, game: set_host_connected(state.game, true)}

      {:player, id} ->
        %{state | game: Game.set_connected(state.game, id, true)}
    end
  end

  defp set_host_connected(game, connected?),
    do: Game.set_connected(game, game.host_player_id, connected?)

  defp remove_conn(state, actor) do
    if actor in Map.values(state.conns) do
      state
    else
      case actor do
        :host ->
          %{state | host_absent_since: state.now.()}
          |> update_game(set_host_connected(state.game, false))
          |> schedule()

        {:player, id} ->
          update_game(state, Game.set_connected(state.game, id, false))
      end
    end
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
      send(pid, {:room_state, Game.view(state.game, actor, now)})
    end

    state
  end

  ## Timers

  defp advance(state) do
    now = state.now.()
    state = update_game(state, Game.tick(state.game, now))

    cond do
      expired?(state.host_absent_since, @host_timeout_ms, now) -> {:close, :host_timeout, state}
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
        state.host_absent_since && state.host_absent_since + @host_timeout_ms,
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

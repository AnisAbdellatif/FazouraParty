defmodule FazouraWeb.RoomChannel do
  @moduledoc """
  Transport adapter for topic `room:<CODE>` (PROTOCOL.md §4–§5). Holds no game logic:
  it maps wire events to `Fazoura.Rooms` intents and pushes what the room sends back.
  """

  use FazouraWeb, :channel

  alias Fazoura.{Game, Moderation, RateLimit, Rooms, RoomSizeCodes}
  alias Fazoura.Rooms.Limits

  @error_messages %{
    unsupported_protocol_version: "This app version is not compatible with the server.",
    room_not_found: "That room doesn't exist or has ended.",
    invalid_token: "Your session for this room is no longer valid.",
    invalid_name: "Names must be 1–20 characters.",
    name_taken: "Someone in the room already has that name.",
    room_full: "This room is full.",
    invalid_phase: "That can't be done right now.",
    not_host: "Only the host can do that.",
    not_player: "Only players can do that.",
    invalid_answer: "Answers must be 1–100 characters.",
    already_submitted: "You already answered this question.",
    unknown_player: "No such player in this room.",
    no_submission: "That player didn't answer this question.",
    paused: "The timer is paused.",
    not_paused: "The timer isn't paused.",
    invalid_payload: "Malformed request.",
    invalid_settings: "Choose 1 question up to the pack size, and 10–120 seconds per question.",
    quiz_required: "Choose a quiz before starting the game.",
    empty_pack: "That quiz has no playable questions.",
    invalid_quiz: "That quiz could not be loaded.",
    quiz_not_found: "That quiz is gone or no longer shared with you.",
    not_connected: "That player isn't connected right now.",
    quiz_not_public: "A public room plays quizzes from the library only.",
    cloud_only: "Only an online room can be listed publicly.",
    name_not_allowed: "That name can't be used in a public room.",
    quiz_too_large: "That quiz's photos are too large to host from here.",
    image_too_large: "A photo in that quiz is over 2 MB.",
    unsupported_image: "A photo in that quiz isn't a JPEG, PNG or WebP.",
    banned: "You can't join public rooms from this connection for now.",
    invalid_room_size: "Choose a room size from the players already here up to the room's limit.",
    invalid_code: "That code doesn't work. Check it with whoever gave it to you.",
    code_expired: "That code has expired.",
    code_used_up: "That code has unlocked as many rooms as it can.",
    rate_limited: "Too many tries from this connection. Wait a minute and try again.",
    too_many_rooms: "The server is too busy for that right now. Try again in a few minutes.",
    removed: "The host removed you from this room.",
    address_full: "Too many players in this room are on your connection already."
  }

  # Failed joins per address per minute. A join is how a room code is tested, and
  # one socket can try as many topics as it likes; unmetered, that finds live private
  # rooms by guessing. Only failures count, so a room of phones on one Wi-Fi
  # reconnecting at once after a blip is never held back.
  @failed_join_limit 30
  @failed_join_window_ms 60_000

  @impl true
  def join("room:" <> code, params, socket) do
    with :ok <- check_join_budget(socket),
         :ok <- check_connection_rooms(socket),
         :ok <- check_protocol_version(params),
         {:ok, reply, room_pid} <- Rooms.join(code, self(), params, moderation(socket)) do
      # Counted against the connection for as long as this channel lives.
      :ok = Limits.joined_over(socket.transport_pid)
      Process.monitor(room_pid)
      {:ok, reply, assign(socket, room_code: code, room_pid: room_pid)}
    else
      {:error, reason} ->
        count_failed_join(socket, reason)
        {:error, error(reason)}
    end
  end

  # One connection may be in only so many rooms (`Fazoura.Rooms.Limits`): otherwise
  # one socket could keep hundreds of rooms alive, since a room lives while anybody
  # is connected to it.
  defp check_connection_rooms(socket) do
    if Limits.may_join?(socket.transport_pid), do: :ok, else: {:error, :rate_limited}
  end

  defp check_join_budget(socket) do
    if join_metered?() and
         RateLimit.exceeded?(
           :failed_joins,
           join_key(socket),
           @failed_join_limit,
           @failed_join_window_ms
         ),
       do: {:error, :rate_limited},
       else: :ok
  end

  # What a guess looks like: a room that isn't there, or a token that isn't its.
  defp count_failed_join(socket, reason) when reason in [:room_not_found, :invalid_token] do
    if join_metered?() do
      RateLimit.check(:failed_joins, join_key(socket), @failed_join_limit, @failed_join_window_ms)
    end

    :ok
  end

  defp count_failed_join(_socket, _reason), do: :ok

  defp join_key(socket), do: socket.assigns[:ip_hash] || "unknown"
  defp join_metered?, do: Application.get_env(:fazoura, :rate_limit_enabled, true)

  # What one channel may send. Every event costs the room process a call, and some
  # much more: choosing quizzes loads them from the database, redeeming a code looks
  # it up there. The general allowance is well above a host overriding a whole room's
  # answers in a hurry; the heavy one is above anybody choosing quizzes by hand.
  @events_per_window 60
  @event_window_ms 10_000
  @heavy_events ["host_select_quiz", "host_redeem_size_code"]
  @heavy_per_window 10
  @heavy_window_ms 60_000

  @impl true
  def handle_in(event, payload, socket) do
    case meter(event) do
      :ok -> handle_event(event, payload, socket)
      {:error, code} -> {:reply, {:error, error(code)}, socket}
    end
  end

  defp meter(event) do
    key = self() |> :erlang.pid_to_list() |> to_string()

    cond do
      not Application.get_env(:fazoura, :rate_limit_enabled, true) ->
        :ok

      RateLimit.check(:channel_events, key, @events_per_window, @event_window_ms) != :ok ->
        {:error, :rate_limited}

      event in @heavy_events and
          RateLimit.check(:heavy_events, key, @heavy_per_window, @heavy_window_ms) != :ok ->
        {:error, :rate_limited}

      true ->
        :ok
    end
  end

  # The code is looked up and counted here, in the channel process, because the room
  # never reads the database during play (AGENTS.md §4). The room is asked first,
  # so a code it already took is not counted twice and a player's attempt costs
  # nothing; a use counted for a room that then refuses it is given back (§6.5).
  defp handle_event("host_redeem_size_code", %{"code" => typed}, socket)
       when is_binary(typed) and byte_size(typed) <= 64 do
    room = socket.assigns.room_code

    # Whether this connection may unlock the room at all comes first: it costs the
    # room one message, where looking the code up costs the database a query, and
    # nobody but the host should be able to make the server run those.
    with :ok <- Rooms.intent(room, self(), :check_unlock),
         {:ok, code} <- RoomSizeCodes.find(typed),
         :new <- Rooms.intent(room, self(), {:check_size_code, code}),
         {:ok, code} <- RoomSizeCodes.take(code) do
      case Rooms.intent(room, self(), {:redeem_size_code, code}) do
        :ok ->
          {:reply, {:ok, %{}}, socket}

        other ->
          RoomSizeCodes.refund(code)
          redeem_reply(other, socket)
      end
    else
      other -> redeem_reply(other, socket)
    end
  end

  defp handle_event(event, payload, socket) do
    with {:ok, intent} <- to_intent(event, payload),
         :ok <- Rooms.intent(socket.assigns.room_code, self(), intent) do
      {:reply, {:ok, %{}}, socket}
    else
      {:error, code} -> {:reply, {:error, error(code)}, socket}
    end
  end

  @impl true
  # Hibernating compacts the heap. Encoding a snapshot grows it, and between one
  # snapshot and the next nearly all of it is garbage: ~170 KB per player, measured,
  # against ~3 KB live (decisions.md, Connection Memory). A hibernated process wakes
  # for the next message at the cost of one small collection.
  def handle_info({:room_state, view}, socket) do
    push(socket, "state", view)
    {:noreply, socket, :hibernate}
  end

  def handle_info({:room_closed, reason}, socket) do
    push(socket, "room_closed", %{reason: Atom.to_string(reason)})
    {:stop, :normal, socket}
  end

  def handle_info({:DOWN, _ref, :process, pid, _reason}, %{assigns: %{room_pid: pid}} = socket) do
    push(socket, "room_closed", %{reason: "shutdown"})
    {:stop, :normal, socket}
  end

  # The major only. A server may be several minors ahead of a phone that has not
  # taken an update yet, and refusing it would end the party over a difference
  # the client does not need to know about (PROTOCOL.md §1).
  defp check_protocol_version(%{"protocol_version" => version}) do
    if version == Game.protocol_major(), do: :ok, else: {:error, :unsupported_protocol_version}
  end

  defp check_protocol_version(_params), do: {:error, :unsupported_protocol_version}

  # Looked up here, in the channel process, so the room itself never reads the
  # database during play (AGENTS.md §4). A socket that never went through
  # `UserSocket.connect/3` — a test's — has no address, and is never banned.
  defp moderation(socket) do
    ip_hash = socket.assigns[:ip_hash]
    %{ip_hash: ip_hash, banned?: Moderation.banned?(ip_hash)}
  end

  defp to_intent("submit", payload), do: {:ok, {:submit, payload}}
  defp to_intent("host_next", _payload), do: {:ok, :next}
  defp to_intent("host_pause", _payload), do: {:ok, :pause}
  defp to_intent("host_resume", _payload), do: {:ok, :resume}
  defp to_intent("host_override", payload), do: {:ok, {:override, payload}}
  defp to_intent("host_configure", payload), do: {:ok, {:configure, payload}}
  defp to_intent("host_select_quiz", payload), do: {:ok, {:select_quiz, payload}}
  defp to_intent("host_rematch", _payload), do: {:ok, :rematch}
  defp to_intent("host_transfer", payload), do: {:ok, {:transfer, payload}}
  defp to_intent("host_close", _payload), do: {:ok, :close}
  defp to_intent("host_set_listed", payload), do: {:ok, {:set_listed, payload}}
  defp to_intent("host_remove_player", payload), do: {:ok, {:remove_player, payload}}
  defp to_intent("host_set_room_size", payload), do: {:ok, {:set_room_size, payload}}
  defp to_intent(_event, _payload), do: {:error, :invalid_payload}

  # `:already`: this room took the code before, which is success, not a second use.
  defp redeem_reply(:already, socket), do: {:reply, {:ok, %{}}, socket}
  defp redeem_reply({:error, code}, socket), do: {:reply, {:error, error(code)}, socket}

  defp error(code), do: %{code: Atom.to_string(code), message: Map.fetch!(@error_messages, code)}
end

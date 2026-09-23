defmodule FazouraWeb.RoomChannel do
  @moduledoc """
  Transport adapter for topic `room:<CODE>` (PROTOCOL.md §4–§5). Holds no game logic:
  it maps wire events to `Fazoura.Rooms` intents and pushes what the room sends back.
  """

  use FazouraWeb, :channel

  alias Fazoura.{Game, Moderation, Rooms}

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
    banned: "You can't join public rooms from this connection for now."
  }

  @impl true
  def join("room:" <> code, params, socket) do
    with :ok <- check_protocol_version(params),
         {:ok, reply, room_pid} <- Rooms.join(code, self(), params, moderation(socket)) do
      Process.monitor(room_pid)
      {:ok, reply, assign(socket, room_code: code, room_pid: room_pid)}
    else
      {:error, code} -> {:error, error(code)}
    end
  end

  @impl true
  def handle_in(event, payload, socket) do
    with {:ok, intent} <- to_intent(event, payload),
         :ok <- Rooms.intent(socket.assigns.room_code, self(), intent) do
      {:reply, {:ok, %{}}, socket}
    else
      {:error, code} -> {:reply, {:error, error(code)}, socket}
    end
  end

  @impl true
  def handle_info({:room_state, view}, socket) do
    push(socket, "state", view)
    {:noreply, socket}
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
  defp to_intent(_event, _payload), do: {:error, :invalid_payload}

  defp error(code), do: %{code: Atom.to_string(code), message: Map.fetch!(@error_messages, code)}
end

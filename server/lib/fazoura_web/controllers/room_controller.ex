defmodule FazouraWeb.RoomController do
  use FazouraWeb, :controller

  import FazouraWeb.ApiHelpers, only: [error: 4, owner_key: 1, report_counts?: 1]

  alias Fazoura.{Moderation, Quizzes, Rooms}
  alias Fazoura.Quizzes.Reports
  alias Fazoura.Rooms.Images

  action_fallback FazouraWeb.FallbackController

  # POST /api/rooms (PROTOCOL.md §3.1). `listed: true` puts the room on the public
  # list (§3.5); it is the one key that may come with any of the forms below.
  def create(conn, %{"listed" => listed} = params) when is_boolean(listed),
    do: create(conn, Map.delete(params, "listed"), listed: listed, creator: creator(conn))

  def create(conn, %{"listed" => _}), do: invalid_listed(conn)
  def create(conn, params), do: create(conn, params, creator: creator(conn))

  # One address may hold only so many rooms at once (`Fazoura.Rooms.Limits`).
  defp creator(conn), do: FazouraWeb.ClientIp.from_conn(conn)

  defp create(conn, params, opts) when map_size(params) == 0 do
    with {:ok, room_code, host_token} <-
           Rooms.create(%Fazoura.Game.Pack{titles: [], questions: []}, opts) do
      created(conn, room_code, host_token)
    end
  end

  # A listed room plays published quizzes only, so it cannot be opened with one
  # that was sent inline.
  defp create(conn, %{"quiz" => _}, [listed: true] ++ _) do
    error(
      conn,
      :unprocessable_entity,
      "quiz_not_public",
      "A public room plays quizzes from the library only."
    )
  end

  # Either a private quiz sent inline as `quiz` (QUIZ_FORMAT.md §5.7), or a stored
  # one by `quiz_id` (`pack_id` is the legacy name).
  defp create(conn, %{"quiz" => %{} = document}, opts) do
    with {:ok, pack, image_keys, _bytes} <- Quizzes.inline_pack(document) do
      case Rooms.create(pack, Keyword.put(opts, :image_keys, image_keys)) do
        {:ok, room_code, host_token} ->
          created(conn, room_code, host_token)

        error ->
          Images.delete(image_keys)
          error
      end
    end
  end

  defp create(conn, params, opts) do
    with {:ok, quiz} <- Quizzes.fetch(params["quiz_id"] || params["pack_id"]),
         {:ok, room_code, host_token} <- Rooms.create(Quizzes.to_pack(quiz), opts) do
      created(conn, room_code, host_token)
    end
  end

  # GET /api/rooms (PROTOCOL.md §3.5): the rooms their hosts chose to list. No
  # token, since that is the point; only listed rooms are in it, so it tells nobody
  # anything about a room that is joined by code.
  def index(conn, _params), do: json(conn, %{rooms: Rooms.listed()})

  # GET /api/rooms/:code (PROTOCOL.md §3.1). The host token travels in a header
  # rather than the path, so it stays out of access logs and referrers.
  def show(conn, %{"code" => code}) do
    token = conn |> get_req_header("x-host-token") |> List.first()

    with {:ok, status} <- Rooms.status(code, token) do
      json(conn, status)
    end
  end

  # POST /api/rooms/:code/report (QUIZ_FORMAT.md §5.9): report the quiz a
  # question in this room came from.
  #
  # This exists because the room is where content is actually seen — browsing
  # only shows a title, a description and tags, so a player who is looking at a
  # question has nowhere else to say something about it. The room resolves the
  # question to its quiz server-side; the id is never broadcast, since a quiz id
  # during a game is a cheat button (`GET /api/quizzes/:id/download`).
  #
  # A token from the room is required, so this cannot be used to find live games
  # by guessing codes — the same reason `GET /api/rooms/:code` wants one.
  #
  # With `player_id` instead, it reports a player — their name, or what they answered
  # (PROTOCOL.md §3.5). The room hands over what was on the screen and the keyed hash
  # of the player's address, and that is all a report about somebody without an
  # account can hold.
  def report(conn, %{"code" => code, "player_id" => player_id} = params)
      when is_binary(player_id) do
    with {:ok, reported} <- Rooms.player_report(code, player_id, room_token(conn)),
         true <- report_counts?(conn) or :dropped,
         {:ok, _report} <- Moderation.report_player(reported, owner_key(conn), params) do
      send_resp(conn, :no_content, "")
    else
      :dropped -> send_resp(conn, :no_content, "")
      error -> error
    end
  end

  def report(conn, %{"code" => code} = params) do
    token = room_token(conn)

    with {:ok, quiz_id} <- Rooms.source_quiz(code, params["question_id"], token),
         true <- report_counts?(conn) or :dropped,
         {:ok, _report} <- Reports.submit(quiz_id, owner_key(conn), params) do
      send_resp(conn, :no_content, "")
    else
      :dropped -> send_resp(conn, :no_content, "")
      error -> error
    end
  end

  defp room_token(conn) do
    conn
    |> get_req_header("x-player-token")
    |> List.first() || conn |> get_req_header("x-host-token") |> List.first()
  end

  defp invalid_listed(conn),
    do: error(conn, :unprocessable_entity, "invalid_payload", "`listed` must be true or false.")

  defp created(conn, room_code, host_token) do
    conn
    |> put_status(:created)
    |> json(%{room_code: room_code, host_token: host_token})
  end
end

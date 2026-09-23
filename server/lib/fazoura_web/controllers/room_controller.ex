defmodule FazouraWeb.RoomController do
  use FazouraWeb, :controller

  import FazouraWeb.ApiHelpers, only: [owner_key: 1]

  alias Fazoura.{Quizzes, Rooms}
  alias Fazoura.Quizzes.Reports
  alias Fazoura.Rooms.Images

  action_fallback FazouraWeb.FallbackController

  def create(conn, params) when map_size(params) == 0 do
    with {:ok, room_code, host_token} <-
           Rooms.create(%Fazoura.Game.Pack{titles: [], questions: []}) do
      created(conn, room_code, host_token)
    end
  end

  # POST /api/rooms (PROTOCOL.md §3.1, QUIZ_FORMAT.md §5.7): either a private quiz sent
  # inline as `quiz`, or a stored one by `quiz_id` (`pack_id` is the legacy name).
  def create(conn, %{"quiz" => %{} = document}) do
    with {:ok, pack, image_keys, _bytes} <- Quizzes.inline_pack(document) do
      case Rooms.create(pack, image_keys: image_keys) do
        {:ok, room_code, host_token} ->
          created(conn, room_code, host_token)

        error ->
          Images.delete(image_keys)
          error
      end
    end
  end

  def create(conn, params) do
    with {:ok, quiz} <- Quizzes.fetch(params["quiz_id"] || params["pack_id"]),
         {:ok, room_code, host_token} <- Rooms.create(Quizzes.to_pack(quiz)) do
      created(conn, room_code, host_token)
    end
  end

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
  def report(conn, %{"code" => code} = params) do
    token =
      conn
      |> get_req_header("x-player-token")
      |> List.first() || conn |> get_req_header("x-host-token") |> List.first()

    with {:ok, quiz_id} <- Rooms.source_quiz(code, params["question_id"], token),
         {:ok, _report} <- Reports.submit(quiz_id, owner_key(conn), params) do
      send_resp(conn, :no_content, "")
    end
  end

  defp created(conn, room_code, host_token) do
    conn
    |> put_status(:created)
    |> json(%{room_code: room_code, host_token: host_token})
  end
end

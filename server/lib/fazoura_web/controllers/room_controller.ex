defmodule FazouraWeb.RoomController do
  use FazouraWeb, :controller

  import FazouraWeb.ApiHelpers, only: [owner_key: 1]

  alias Fazoura.{Quizzes, Rooms}

  action_fallback FazouraWeb.FallbackController

  # POST /api/rooms (PROTOCOL.md §3.1, QUIZ_FORMAT.md §5.7). `pack_id` is the legacy
  # name for `quiz_id`. Private quizzes need the owner's x-owner-key header.
  def create(conn, params) do
    with {:ok, quiz} <-
           Quizzes.fetch_visible(params["quiz_id"] || params["pack_id"], owner_key(conn)),
         {:ok, room_code, host_token} <- Rooms.create(Quizzes.to_pack(quiz)) do
      conn
      |> put_status(:created)
      |> json(%{room_code: room_code, host_token: host_token})
    end
  end
end

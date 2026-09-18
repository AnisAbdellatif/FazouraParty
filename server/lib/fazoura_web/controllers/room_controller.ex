defmodule FazouraWeb.RoomController do
  use FazouraWeb, :controller

  alias Fazoura.{Quizzes, Rooms}
  alias Fazoura.Rooms.Images

  action_fallback FazouraWeb.FallbackController

  def create(conn, params) when map_size(params) == 0 do
    with {:ok, room_code, host_token} <-
           Rooms.create(%Fazoura.Game.Pack{id: "unselected", title: "", questions: []}) do
      created(conn, room_code, host_token)
    end
  end

  # POST /api/rooms (PROTOCOL.md §3.1, QUIZ_FORMAT.md §5.7): either a private quiz sent
  # inline as `quiz`, or a stored one by `quiz_id` (`pack_id` is the legacy name).
  def create(conn, %{"quiz" => %{} = document}) do
    with {:ok, pack, image_keys} <- Quizzes.inline_pack(document) do
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

  defp created(conn, room_code, host_token) do
    conn
    |> put_status(:created)
    |> json(%{room_code: room_code, host_token: host_token})
  end
end

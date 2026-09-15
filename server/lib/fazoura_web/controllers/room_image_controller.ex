defmodule FazouraWeb.RoomImageController do
  @moduledoc "Serves private-quiz photos while their room is alive (QUIZ_FORMAT.md §5.7)."

  use FazouraWeb, :controller

  import FazouraWeb.ApiHelpers, only: [error: 4]

  alias Fazoura.Rooms.Images

  def show(conn, %{"key" => key}) do
    case Images.fetch(key) do
      {:ok, content_type, binary} ->
        conn
        |> put_resp_content_type(content_type, nil)
        |> put_resp_header("cache-control", "private, max-age=3600")
        |> send_resp(200, binary)

      :error ->
        error(conn, :not_found, "image_not_found", "That photo is no longer available.")
    end
  end
end

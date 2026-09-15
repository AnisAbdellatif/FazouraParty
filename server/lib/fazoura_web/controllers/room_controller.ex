defmodule FazouraWeb.RoomController do
  use FazouraWeb, :controller

  alias Fazoura.Game.Pack
  alias Fazoura.Rooms

  # POST /api/rooms (PROTOCOL.md §3.1)
  def create(conn, params) do
    with {:ok, pack} <- Pack.fetch(params["pack_id"]),
         {:ok, room_code, host_token} <- Rooms.create(pack) do
      conn
      |> put_status(:created)
      |> json(%{room_code: room_code, host_token: host_token})
    else
      {:error, :pack_not_found} ->
        conn |> put_status(:not_found) |> json(%{code: "pack_not_found"})

      {:error, :empty_pack} ->
        conn |> put_status(:unprocessable_entity) |> json(%{code: "empty_pack"})
    end
  end
end

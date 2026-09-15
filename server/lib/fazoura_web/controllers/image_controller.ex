defmodule FazouraWeb.ImageController do
  @moduledoc "Question photo uploads (QUIZ_FORMAT.md §5.6)."

  use FazouraWeb, :controller

  import FazouraWeb.ApiHelpers, only: [owner_key: 1, error: 4]

  alias Fazoura.{Quizzes, Uploads}

  action_fallback FazouraWeb.FallbackController

  def create(conn, %{"file" => %Plug.Upload{path: path}}) do
    with {:ok, binary} <- File.read(path),
         {:ok, image} <- Quizzes.store_image(binary, owner_key(conn)) do
      conn
      |> put_status(:created)
      |> json(%{key: image.key, url: Uploads.url(image.key)})
    end
  end

  def create(conn, _params),
    do:
      error(
        conn,
        :unprocessable_entity,
        "missing_file",
        "Send the image as a multipart file part."
      )
end

defmodule FazouraWeb.Admin.QuizController do
  @moduledoc """
  Downloading a quiz from the dashboard as a `.fazoura` package (ADMIN.md §3.4).

  The public API sends the same bytes at `GET /api/quizzes/:id/archive`, but metered at
  ten a minute — a rate for a guest saving a quiz for offline play, not for an admin
  taking a backup or moving a quiz to another server. This route answers to the
  dashboard's own credentials instead.
  """

  use FazouraWeb, :controller

  alias Fazoura.{Admin, Quizzes}

  @spec archive(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def archive(conn, %{"id" => id}) do
    with {:ok, quiz} <- Admin.fetch_quiz(id),
         {:ok, binary} <- Quizzes.archive(quiz) do
      conn
      |> put_resp_content_type("application/zip")
      |> put_resp_header("content-disposition", ~s(attachment; filename="#{filename(quiz)}"))
      |> send_resp(200, binary)
    else
      {:error, :quiz_not_found} ->
        send_error(conn, 404, "That quiz is gone.")

      # A photo the quiz still points at that the uploads volume no longer has. The
      # point of a package is that it is self-contained, so this is an error rather
      # than a package with a hole in it.
      {:error, :image_not_found} ->
        send_error(conn, 409, "A photo this quiz uses is missing from the uploads volume.")
    end
  end

  # The slug when it has one, so re-importing the file keeps the name it is hostable by
  # (QUIZ_FORMAT.md §6).
  defp filename(quiz), do: "#{quiz.slug || quiz.id}.fazoura"

  defp send_error(conn, status, message) do
    conn |> put_resp_content_type("text/plain") |> send_resp(status, message)
  end
end

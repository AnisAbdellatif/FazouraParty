defmodule FazouraWeb.QuizController do
  @moduledoc "Quiz browsing and custom quiz management (QUIZ_FORMAT.md §5.1–5.5)."

  use FazouraWeb, :controller

  import FazouraWeb.ApiHelpers, only: [owner_key: 1, int_param: 2]

  alias Fazoura.Quizzes

  action_fallback FazouraWeb.FallbackController

  def index(conn, params) do
    key = owner_key(conn)

    opts = [
      scope: params["scope"] || "public",
      owner_key: key,
      q: params["q"],
      category: params["category"],
      limit: int_param(params["limit"], 20),
      offset: int_param(params["offset"], 0)
    ]

    with {:ok, quizzes, next_offset} <- Quizzes.list(opts) do
      json(conn, %{
        quizzes:
          Enum.map(quizzes, fn quiz ->
            Quizzes.to_document(quiz, owner?: Quizzes.owner?(quiz, key), questions: false)
          end),
        next_offset: next_offset
      })
    end
  end

  def show(conn, %{"id" => id}) do
    key = owner_key(conn)

    with {:ok, quiz} <- Quizzes.fetch_visible(id, key) do
      json(conn, Quizzes.to_document(quiz, owner?: Quizzes.owner?(quiz, key)))
    end
  end

  def create(conn, _params) do
    with {:ok, quiz} <- Quizzes.create(conn.body_params, owner_key(conn)) do
      conn |> put_status(:created) |> render_owned(quiz)
    end
  end

  def update(conn, %{"id" => id}) do
    with {:ok, quiz} <- Quizzes.replace(id, conn.body_params, owner_key(conn)) do
      render_owned(conn, quiz)
    end
  end

  def set_visibility(conn, %{"id" => id} = params) do
    with {:ok, quiz} <- Quizzes.set_visibility(id, params["visibility"], owner_key(conn)) do
      render_owned(conn, quiz)
    end
  end

  def delete(conn, %{"id" => id}) do
    with :ok <- Quizzes.delete(id, owner_key(conn)) do
      send_resp(conn, :no_content, "")
    end
  end

  defp render_owned(conn, quiz) do
    quiz = Fazoura.Repo.preload(quiz, :questions, force: true)
    json(conn, Quizzes.to_document(quiz, owner?: true))
  end
end

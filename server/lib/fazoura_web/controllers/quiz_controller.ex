defmodule FazouraWeb.QuizController do
  @moduledoc "Public quiz browsing and publishing (QUIZ_FORMAT.md §5.1–5.6)."

  use FazouraWeb, :controller

  import FazouraWeb.ApiHelpers, only: [owner_key: 1, int_param: 2]

  alias Fazoura.Quizzes

  action_fallback FazouraWeb.FallbackController

  def index(conn, params) do
    key = owner_key(conn)

    opts = [
      q: params["q"],
      tag: params["tag"],
      limit: int_param(params["limit"], 20),
      offset: int_param(params["offset"], 0)
    ]

    {:ok, quizzes, next_offset} = Quizzes.list(opts)

    json(conn, %{
      quizzes:
        Enum.map(quizzes, fn quiz ->
          Quizzes.to_document(quiz, owner?: Quizzes.owner?(quiz, key), questions: false)
        end),
      next_offset: next_offset
    })
  end

  # GET /api/tags: the tags public quizzes actually use, most used first, plus the
  # suggested quick picks an admin maintains (§5.2).
  def tags(conn, params) do
    json(conn, %{
      tags: Quizzes.popular_tags(int_param(params["limit"], 30)),
      suggested: Fazoura.Settings.suggested_tags()
    })
  end

  def show(conn, %{"id" => id}) do
    key = owner_key(conn)

    with {:ok, quiz} <- Quizzes.fetch(id) do
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

  def delete(conn, %{"id" => id}) do
    with :ok <- Quizzes.delete(id, owner_key(conn)) do
      send_resp(conn, :no_content, "")
    end
  end

  defp render_owned(conn, quiz) do
    quiz = Fazoura.Repo.preload(quiz, [:questions, :quiz_tags], force: true)
    json(conn, Quizzes.to_document(quiz, owner?: true))
  end
end

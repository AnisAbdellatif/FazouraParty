defmodule FazouraWeb.QuizController do
  @moduledoc "Public quiz browsing and publishing (QUIZ_FORMAT.md §5.1–5.6)."

  use FazouraWeb, :controller

  import FazouraWeb.ApiHelpers, only: [owner_key: 1, int_param: 2, error: 4, report_counts?: 1]

  alias Fazoura.{Quizzes, RateLimit}
  alias Fazoura.Quizzes.{Reports, Review}
  alias Fazoura.Rooms.Listing

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

  # An explicit download is the opt-in answer leak required to play a
  # community quiz offline. Normal browsing remains summary-only.
  def download(conn, %{"id" => id}) do
    key = owner_key(conn)

    with {:ok, quiz} <- Quizzes.fetch(id),
         :ok <- not_in_play(quiz) do
      json(
        conn,
        Quizzes.to_document(quiz, owner?: Quizzes.owner?(quiz, key), with_answers: true)
      )
    end
  end

  def archive(conn, %{"id" => id}) do
    with {:ok, quiz} <- Quizzes.fetch(id),
         :ok <- not_in_play(quiz),
         {:ok, binary} <- Quizzes.archive(quiz) do
      conn
      |> put_resp_content_type("application/zip")
      |> put_resp_header(
        "content-disposition",
        ~s(attachment; filename="#{quiz.slug || quiz.id}.fazoura")
      )
      |> send_resp(200, binary)
    end
  end

  # Publishing is a submission (§4, §5.4). The device sends one `.fazoura` and
  # it waits in the queue; no quiz row and no photo on disk until somebody has
  # read it.
  def create(conn, %{"file" => %Plug.Upload{path: path}}) do
    with {:ok, package} <- File.read(path),
         :ok <- meter_submission(conn, package),
         {:ok, submission} <- Review.submit(package, owner_key(conn)) do
      conn |> put_status(:created) |> json(Review.to_document(submission))
    end
  end

  def create(conn, _params), do: package_required(conn)

  # Editing a public quiz comes back through the queue too. Otherwise the review
  # means nothing: publish something harmless, then swap its contents.
  def update(conn, %{"id" => id, "file" => %Plug.Upload{path: path}}) do
    with {:ok, package} <- File.read(path),
         :ok <- meter_submission(conn, package),
         {:ok, submission} <- Review.submit(package, owner_key(conn), replaces: id) do
      json(conn, Review.to_document(submission))
    end
  end

  def update(conn, _params), do: package_required(conn)

  @doc "What this device has sent for review, and what became of it (§5.4a)."
  def submissions(conn, _params) do
    json(conn, %{
      submissions: Enum.map(Review.for_owner(owner_key(conn)), &Review.to_document/1)
    })
  end

  def withdraw(conn, %{"id" => id}) do
    with :ok <- Review.withdraw(id, owner_key(conn)) do
      send_resp(conn, :no_content, "")
    end
  end

  # A client old enough to send a JSON document predates the queue. Rebuilding
  # the package here would mean its photos were uploaded first and are already
  # on disk unreviewed, which is the one thing this is for — so it is told to
  # update instead, which it can do from inside the app.
  defp package_required(conn) do
    error(
      conn,
      :unprocessable_entity,
      "package_required",
      "Update the app: a quiz is now submitted for review as a .fazoura file part."
    )
  end

  def delete(conn, %{"id" => id}) do
    with :ok <- Quizzes.delete(id, owner_key(conn)) do
      send_resp(conn, :no_content, "")
    end
  end

  # Reporting a published quiz (§5.9). Anyone may report anything public; the
  # key is here to count devices rather than taps, not to decide who may.
  #
  # The answer says nothing about what happened to the report — not whether it
  # is the first, not how many others there are, not whether an admin has
  # already dismissed one. That is moderation state, and handing it back would
  # let anybody probe it.
  def report(conn, %{"id" => id} = params) do
    if report_counts?(conn) do
      with {:ok, _report} <- Reports.submit(id, owner_key(conn), params) do
        send_resp(conn, :no_content, "")
      end
    else
      send_resp(conn, :no_content, "")
    end
  end

  # Both carry every accepted answer (§5.3a, §5.3b); see `Rooms.Listing.in_play?/1`.
  defp not_in_play(quiz),
    do: if(Listing.in_play?(quiz.id), do: {:error, :quiz_in_play}, else: :ok)

  # What one address may put in the review queue in a day, by count and by bytes. The
  # queue's per-key cap cannot do this: a publisher key is whatever the caller sends,
  # so a caller with several could fill the queue for everybody within minutes.
  @submissions_per_day 10
  @submission_bytes_per_day 128 * 1024 * 1024
  @day_ms 86_400_000

  defp meter_submission(conn, package) do
    address = FazouraWeb.ClientIp.from_conn(conn)

    if Application.get_env(:fazoura, :rate_limit_enabled, true) do
      with :ok <- RateLimit.check(:submissions, address, @submissions_per_day, @day_ms),
           :ok <-
             RateLimit.check(
               :submission_bytes,
               address,
               @submission_bytes_per_day,
               @day_ms,
               max(byte_size(package), 1)
             ) do
        :ok
      else
        {:error, :rate_limited} -> {:error, :daily_submissions}
      end
    else
      :ok
    end
  end
end

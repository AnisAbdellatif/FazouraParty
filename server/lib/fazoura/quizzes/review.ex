defmodule Fazoura.Quizzes.Review do
  @moduledoc """
  The queue between writing a quiz and it being public (QUIZ_FORMAT.md §4,
  ADMIN.md §3.2).

  A submission is the `.fazoura` package the device sent and nothing else. It is
  not a quiz, it has no rows in `quizzes` or `questions`, and its photos are not
  in the uploads volume — so nothing anybody has written can be found, hosted or
  served until somebody has read it. Approving unpacks the package through the
  same path a preset takes (`Quizzes.read_archive/1`), and only then does a quiz
  exist.

  Nothing is lost by waiting: the author still holds the document on their own
  device and hosts it inline, which never touches the server at all.
  """

  import Ecto.Query

  alias Fazoura.Quizzes
  alias Fazoura.Quizzes.{Archive, OwnerKey, Reports, Submission}
  alias Fazoura.Repo

  @type reason :: :owner_key_required | :not_found | Archive.reason() | :invalid_quiz

  @doc """
  Takes a `.fazoura` package and puts it in the queue.

  The package is read far enough to know it is one and to label the queue, and
  no further: it is untrusted input that nobody has looked at yet, so it is
  stored as the bytes that arrived rather than unpacked into anything.
  """
  @spec submit(binary(), String.t() | nil, keyword()) ::
          {:ok, Submission.t()} | {:error, reason() | Ecto.Changeset.t()}
  def submit(package, owner_key, opts \\ [])

  def submit(package, owner_key, opts) when is_binary(package) do
    with {:ok, hash} <- hash_key(owner_key),
         {:ok, replaces} <- replaced_quiz(opts[:replaces], hash),
         {:ok, %{document: document}} <- Archive.read(package),
         {:ok, summary} <- summarise(document) do
      %Submission{}
      |> Submission.changeset(
        Map.merge(summary, %{
          package: package,
          owner_key_hash: hash,
          replaces_quiz_id: replaces
        })
      )
      |> Repo.insert()
    end
  end

  def submit(_package, _owner_key, _opts), do: {:error, :invalid_quiz}

  # An edit may only be offered for a quiz this device published; anybody
  # else's does not exist to it (§4 — 404, never 403).
  defp replaced_quiz(nil, _hash), do: {:ok, nil}

  defp replaced_quiz(id, hash) do
    case Quizzes.fetch(id) do
      {:ok, %{owner_key_hash: ^hash} = quiz} -> {:ok, quiz.id}
      _ -> {:error, :not_found}
    end
  end

  @doc "Submissions waiting to be read, oldest first."
  @spec pending(pos_integer()) :: [Submission.t()]
  def pending(limit \\ 50) do
    Repo.all(
      from s in Submission,
        where: s.status == "pending",
        order_by: [asc: s.submitted_at],
        limit: ^(limit |> max(1) |> min(200))
    )
  end

  @doc "How many are waiting, for the dashboard's badge."
  @spec pending_count() :: non_neg_integer()
  def pending_count,
    do: Repo.aggregate(from(s in Submission, where: s.status == "pending"), :count)

  @doc "One submission, whatever its state."
  @spec fetch(term()) :: {:ok, Submission.t()} | {:error, :not_found}
  def fetch(id) when is_binary(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> Repo.get(Submission, uuid) |> or_missing()
      :error -> {:error, :not_found}
    end
  end

  def fetch(_id), do: {:error, :not_found}

  @doc "What this device has sent, newest first. Its own submissions only."
  @spec for_owner(String.t() | nil) :: [Submission.t()]
  def for_owner(owner_key) do
    case hash_key(owner_key) do
      {:ok, hash} ->
        Repo.all(
          from s in Submission,
            where: s.owner_key_hash == ^hash,
            order_by: [desc: s.submitted_at]
        )

      _ ->
        []
    end
  end

  @doc """
  The package itself, for an admin to look at before deciding.

  Read rather than trusted: this is the one place unreviewed content is
  inflated, and `Archive.read/1` caps and checks it before anything is.
  """
  @spec contents(Submission.t()) :: {:ok, map()} | {:error, Archive.reason()}
  def contents(%Submission{package: package}) do
    with {:ok, %{document: document, photos: photos}} <- Archive.read(package) do
      {:ok, %{document: document, photos: photos}}
    end
  end

  @doc """
  Publishes a submission. Its photos move into the uploads volume here, and not
  before, so nothing unreviewed is ever served from disk.
  """
  @spec approve(term()) :: {:ok, Quizzes.Quiz.t()} | {:error, reason() | Ecto.Changeset.t()}
  def approve(id) do
    with {:ok, submission} <- fetch(id),
         {:ok, params} <- Quizzes.read_archive(submission.package),
         {:ok, quiz} <- publish(submission, params) do
      submission
      |> Ecto.Changeset.change(
        status: "approved",
        quiz_id: quiz.id,
        review_note: nil,
        reviewed_at: DateTime.utc_now(:second),
        # The quiz carries the content now; keeping a second copy of every
        # photo in a blob nobody reads again is just disk.
        package: <<>>
      )
      |> Repo.update()

      {:ok, quiz}
    end
  end

  @doc """
  Turns a submission down, with a note its author's device can show.

  The row is kept — without the package, which has served its purpose — so the
  answer survives long enough to be read.
  """
  @spec reject(term(), String.t() | nil) :: {:ok, Submission.t()} | {:error, :not_found}
  def reject(id, note) do
    with {:ok, submission} <- fetch(id) do
      submission
      |> Ecto.Changeset.change(
        status: "rejected",
        review_note: note,
        reviewed_at: DateTime.utc_now(:second),
        package: <<>>
      )
      |> Repo.update()
    end
  end

  @doc "Withdraws a submission. The device that sent it, and nobody else."
  @spec withdraw(term(), String.t() | nil) :: :ok | {:error, :not_found}
  def withdraw(id, owner_key) do
    with {:ok, hash} <- hash_key(owner_key),
         {:ok, submission} <- fetch(id),
         true <- submission.owner_key_hash == hash do
      Repo.delete(submission)
      :ok
    else
      # Somebody else's submission does not exist, rather than being refused
      # (§4 — 404, never 403).
      _ -> {:error, :not_found}
    end
  end

  # An edit replaces the quiz it was offered against, keeping its id — so a
  # device that saved it, or a room that has it selected, is looking at the
  # same quiz rather than a second copy.
  defp publish(%Submission{replaces_quiz_id: nil} = submission, params),
    do: Quizzes.publish_reviewed(params, submission.owner_key_hash)

  defp publish(%Submission{replaces_quiz_id: id}, params) do
    with {:ok, quiz} <- Quizzes.fetch(id) do
      Quizzes.replace_document(quiz, params)
    end
  end

  @doc """
  Forgets submissions that have been decided, once the decision is old enough.

  An approved one has done its job: the quiz carries the content and the
  publisher key now, so the row is a second copy of who published what. A
  rejected one is kept for its note, which is a message to its author — and a
  message nobody has come back for in three months is not worth keeping
  forever (GDPR Art. 5(1)(e)).

  Pending submissions are never swept: deleting somebody's unread request
  because nobody got to it would be the queue failing quietly. Emptying it is
  what `/admin/review` is for.

  Options: `:retention_days`, `:now` (a `DateTime`, for tests).
  """
  @spec sweep(keyword()) :: non_neg_integer()
  def sweep(opts \\ []) do
    {count, _} =
      Submission
      |> where([s], s.status in ["approved", "rejected"])
      |> where([s], s.reviewed_at < ^Reports.cutoff(opts))
      |> Repo.delete_all()

    count
  end

  @doc "What a device is told about something it submitted (QUIZ_FORMAT.md §5.4)."
  @spec to_document(Submission.t()) :: map()
  def to_document(%Submission{} = submission) do
    %{
      id: submission.id,
      title: submission.title,
      status: submission.status,
      question_count: submission.question_count,
      has_photos: submission.has_photos,
      # Only ever sent to the device that submitted it; a rejection is a message
      # to its author, not something published beside a quiz.
      review_note: submission.review_note,
      quiz_id: submission.quiz_id,
      replaces_quiz_id: submission.replaces_quiz_id,
      submitted_at: submission.submitted_at,
      reviewed_at: submission.reviewed_at
    }
  end

  defp summarise(document) do
    questions = Map.get(document, "questions") || []
    title = document |> Map.get("title") |> to_title()

    cond do
      title == nil ->
        {:error, :invalid_quiz}

      questions == [] ->
        {:error, :invalid_quiz}

      true ->
        {:ok, %{title: title, question_count: length(questions), has_photos: photos?(questions)}}
    end
  end

  defp to_title(title) when is_binary(title) do
    case String.trim(title) do
      "" -> nil
      trimmed -> String.slice(trimmed, 0, 80)
    end
  end

  defp to_title(_title), do: nil

  defp photos?(questions),
    do: Enum.any?(questions, &match?(%{"image" => %{"path" => path}} when is_binary(path), &1))

  defp hash_key(owner_key) do
    case OwnerKey.hash(owner_key) do
      {:ok, hash} -> {:ok, hash}
      _ -> {:error, :owner_key_required}
    end
  end

  defp or_missing(nil), do: {:error, :not_found}
  defp or_missing(submission), do: {:ok, submission}
end

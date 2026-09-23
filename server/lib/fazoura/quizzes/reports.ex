defmodule Fazoura.Quizzes.Reports do
  @moduledoc """
  The queue for published quizzes somebody has objected to (QUIZ_FORMAT.md §5.9,
  ADMIN.md §3.3).

  `Fazoura.Quizzes.Review` is the gate in front of publishing; this is what
  happens after it. The two catch different things: review catches a quiz that
  should never have gone out, reports catch one that did — because a reader was
  wrong, or because its author edited it into something else.

  Reports are grouped by quiz, because that is the unit an admin acts on: a
  quiz is taken down or it is not. Answering a report means deciding about the
  quiz, and both answers clear every open report against it.
  """

  import Ecto.Query

  alias Fazoura.Quizzes
  alias Fazoura.Quizzes.{OwnerKey, Quiz, Report}
  alias Fazoura.Repo

  @type reason :: :owner_key_required | :quiz_not_found | :invalid_report
  @type queued :: %{
          quiz: Quiz.t(),
          reports: [Report.t()],
          count: non_neg_integer(),
          first_reported_at: DateTime.t()
        }

  @doc """
  Records a report against a published quiz.

  A device may report a given quiz once. Reporting it again replaces what that
  device said rather than adding a second voice — the count is read as "how
  many people", so it has to mean that. The first report's timestamp stands,
  since that is when the clock started; and a report an admin has already
  dismissed stays dismissed, so re-reporting cannot undo a decision.
  """
  @spec submit(term(), String.t() | nil, map()) ::
          {:ok, Report.t()} | {:error, reason()}
  def submit(quiz_id, reporter_key, params) do
    with {:ok, hash} <- hash_key(reporter_key),
         {:ok, quiz} <- Quizzes.fetch(quiz_id) do
      %Report{}
      |> Report.changeset(%{
        quiz_id: quiz.id,
        reason: params["reason"],
        note: params["note"],
        reporter_key_hash: hash
      })
      |> Repo.insert(
        # This device reporting the same quiz again is it rewording its
        # complaint, so the latest wording wins — but `reported_at` and
        # `status` are untouched, which keeps the clock running from the first
        # report and stops a dismissal being undone by tapping again.
        on_conflict: [set: [reason: params["reason"], note: trimmed(params["note"])]],
        conflict_target: [:quiz_id, :reporter_key_hash],
        # Without this an upsert answers with the struct the changeset built,
        # so `reported_at` and `status` would read as this attempt's rather
        # than the row's — which is exactly what the two of them are here to
        # remember.
        returning: true
      )
      |> case do
        {:ok, report} -> {:ok, report}
        # The only way to fail validation is a reason the client made up, which
        # is worth a clearer answer than "the quiz has errors".
        {:error, %Ecto.Changeset{}} -> {:error, :invalid_report}
      end
    end
  end

  @doc "Quizzes with reports nobody has answered yet, longest-waiting first."
  @spec open(pos_integer()) :: [queued()]
  def open(limit \\ 50) do
    Report
    |> where([r], r.status == "open")
    |> order_by([r], asc: r.reported_at)
    # With its questions and tags: the screen shows what is in the quiz, and an
    # admin deciding whether to take something down should not have to go and
    # look it up somewhere else.
    |> preload(quiz: [:questions, :quiz_tags])
    |> limit(^(limit |> max(1) |> min(500)))
    |> Repo.all()
    |> group_by_quiz()
  end

  @doc "How many quizzes are waiting on an answer, for the dashboard's badge."
  @spec open_count() :: non_neg_integer()
  def open_count do
    Report
    |> where([r], r.status == "open")
    |> distinct(true)
    |> select([r], r.quiz_id)
    |> subquery()
    |> Repo.aggregate(:count)
  end

  @doc """
  Answers every open report against a quiz without taking it down.

  The other answer is deleting the quiz, which takes its reports with it
  (`Fazoura.Admin.delete_quiz/1`).
  """
  @spec dismiss(term()) :: {:ok, non_neg_integer()} | {:error, :quiz_not_found}
  def dismiss(quiz_id) do
    with {:ok, quiz} <- Quizzes.fetch(quiz_id) do
      {count, _} =
        Report
        |> where([r], r.quiz_id == ^quiz.id and r.status == "open")
        |> Repo.update_all(set: [status: "dismissed", reviewed_at: DateTime.utc_now(:second)])

      {:ok, count}
    end
  end

  @doc """
  Forgets reports that have been answered, once the answer is old enough.

  A report is somebody's account of what is wrong with a quiz, in their own
  words, and it is kept only as long as it is any use: to decide, and then
  briefly in case the decision is questioned. After that it is a stranger's
  free text about a stranger's quiz sitting in a database for no reason
  (GDPR Art. 5(1)(e)).

  Open reports are never swept — they are the queue. Reports about a quiz that
  was taken down went with it.

  Options: `:retention_days`, `:now` (a `DateTime`, for tests).
  """
  @spec sweep(keyword()) :: non_neg_integer()
  def sweep(opts \\ []) do
    {count, _} =
      Report
      |> where([r], r.status == "dismissed" and r.reviewed_at < ^cutoff(opts))
      |> Repo.delete_all()

    count
  end

  @doc "When a decided record stops being worth keeping."
  @spec cutoff(keyword()) :: DateTime.t()
  def cutoff(opts) do
    days = Keyword.get(opts, :retention_days, 90)

    opts
    |> Keyword.get(:now, DateTime.utc_now())
    |> DateTime.add(-days * 24 * 60 * 60, :second)
  end

  # One entry per quiz, keeping the order the rows arrived in — which is
  # oldest report first, so a quiz's place in the queue is set by the first
  # person who complained about it rather than the most recent.
  defp group_by_quiz(reports) do
    reports
    |> Enum.group_by(& &1.quiz_id)
    |> Enum.map(fn {_id, [%Report{quiz: quiz} | _] = grouped} ->
      %{
        quiz: quiz,
        reports: grouped,
        count: length(grouped),
        first_reported_at: grouped |> Enum.map(& &1.reported_at) |> Enum.min(DateTime)
      }
    end)
    |> Enum.sort_by(& &1.first_reported_at, DateTime)
  end

  defp trimmed(note) when is_binary(note) do
    case String.trim(note) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp trimmed(note), do: note

  defp hash_key(reporter_key) do
    case OwnerKey.hash(reporter_key) do
      {:ok, hash} -> {:ok, hash}
      _ -> {:error, :owner_key_required}
    end
  end
end

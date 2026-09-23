defmodule Fazoura.Quizzes.ModerationSweepTest do
  @moduledoc """
  What the moderation tables forget, and what they must not.

  Both hold things people wrote about other people. Keeping them while they are
  being acted on is the point; keeping them for ever afterwards is a database
  full of strangers' complaints (GDPR Art. 5(1)(e)).
  """

  use Fazoura.DataCase, async: false

  import Ecto.Query

  alias Ecto.Adapters.SQL.Sandbox
  alias Fazoura.QuizFixtures
  alias Fazoura.Quizzes
  alias Fazoura.Quizzes.{ModerationSweeper, Report, Reports, Review, Submission}

  defp key(letter), do: "k-" <> String.duplicate(letter, 40)

  # Moves a decided record's clock back, so a sweep with the real cutoff sees it
  # as old. Cheaper and clearer than sweeping with a zero-day retention, which
  # would not prove the cutoff is applied at all.
  defp decided_days_ago(queryable, days) do
    Repo.update_all(queryable,
      set: [reviewed_at: DateTime.add(DateTime.utc_now(), -days * 24 * 60 * 60, :second)]
    )
  end

  describe "reports" do
    setup do
      quiz = QuizFixtures.published!(%{"title" => "Reported Once"})
      {:ok, _} = Reports.submit(quiz.id, key("a"), %{"reason" => "spam", "note" => "Nonsense"})
      %{quiz: quiz}
    end

    test "an answered one is forgotten once the answer is old", %{quiz: quiz} do
      {:ok, 1} = Reports.dismiss(quiz.id)
      decided_days_ago(Report, 91)

      assert Reports.sweep() == 1
      assert Repo.aggregate(Report, :count) == 0
    end

    test "but not while the answer is recent", %{quiz: quiz} do
      {:ok, 1} = Reports.dismiss(quiz.id)

      assert Reports.sweep() == 0
      assert Repo.aggregate(Report, :count) == 1
    end

    test "one still waiting is never swept, however old" do
      # The queue is not a retention problem: a report nobody has answered is
      # a report nobody has answered, and deleting it would hide that.
      Repo.update_all(Report,
        set: [reported_at: DateTime.add(DateTime.utc_now(), -365 * 24 * 60 * 60, :second)]
      )

      assert Reports.sweep() == 0
      assert [_still_there] = Reports.open()
    end

    test "the window is how long an answer is kept, and it is configurable", %{quiz: quiz} do
      {:ok, 1} = Reports.dismiss(quiz.id)
      decided_days_ago(Report, 40)

      assert Reports.sweep(retention_days: 90) == 0
      assert Reports.sweep(retention_days: 30) == 1
    end
  end

  describe "submissions" do
    test "a rejected one is forgotten once its note has gone unread long enough" do
      {:ok, submission} = Review.submit(QuizFixtures.package(%{"title" => "No"}), key("b"))
      {:ok, _} = Review.reject(submission.id, "Question 3 is not suitable.")
      decided_days_ago(Submission, 91)

      assert Review.sweep() == 1
      assert Review.for_owner(key("b")) == []
    end

    test "an approved one goes too — the quiz carries all of it now" do
      {:ok, submission} = Review.submit(QuizFixtures.package(%{"title" => "Yes"}), key("c"))
      {:ok, quiz} = Review.approve(submission.id)
      decided_days_ago(Submission, 91)

      assert Review.sweep() == 1
      # The quiz is untouched: sweeping forgets the paperwork, not the content.
      assert {:ok, still_public} = Quizzes.fetch(quiz.id)
      assert still_public.title == "Yes"
    end

    test "a recent decision is left alone, so its author can still read it" do
      {:ok, submission} = Review.submit(QuizFixtures.package(%{"title" => "Maybe"}), key("d"))
      {:ok, _} = Review.reject(submission.id, "Not yet.")

      assert Review.sweep() == 0
      assert [kept] = Review.for_owner(key("d"))
      assert kept.review_note == "Not yet."
    end

    test "one still waiting is never swept, however old" do
      # Deleting somebody's unread request because nobody got to it would be
      # the queue failing quietly.
      {:ok, _} = Review.submit(QuizFixtures.package(%{"title" => "Waiting"}), key("e"))

      Repo.update_all(Submission,
        set: [submitted_at: DateTime.add(DateTime.utc_now(), -365 * 24 * 60 * 60, :second)]
      )

      assert Review.sweep() == 0
      assert [_still_queued] = Review.pending()
    end
  end

  describe "the sweeper process" do
    test "reports both halves of what it forgot" do
      quiz = QuizFixtures.published!()
      {:ok, _} = Reports.submit(quiz.id, key("f"), %{"reason" => "spam"})
      {:ok, 1} = Reports.dismiss(quiz.id)
      {:ok, submission} = Review.submit(QuizFixtures.package(%{"title" => "Old"}), key("g"))
      {:ok, _} = Review.reject(submission.id, "No.")

      decided_days_ago(Report, 91)
      decided_days_ago(Submission, 91)

      # Two submissions, not one: `published!` approves a submission of its own
      # to get a live quiz, and that decision is just as old.
      assert %{reports: 1, submissions: 2} = sweep_through_the_process()
    end

    defp sweep_through_the_process do
      start_supervised!({ModerationSweeper, retention_days: 90})
      # The sandbox connection belongs to this process; the sweeper needs it to
      # see the rows this test just wrote.
      Sandbox.allow(Repo, self(), Process.whereis(ModerationSweeper))
      ModerationSweeper.sweep_now()
    end
  end

  describe "nothing sweeps a quiz" do
    test "a quiz whose reports were swept is still public" do
      quiz = QuizFixtures.published!(%{"title" => "Survives"})
      {:ok, _} = Reports.submit(quiz.id, key("h"), %{"reason" => "spam"})
      {:ok, 1} = Reports.dismiss(quiz.id)
      decided_days_ago(Report, 91)

      assert Reports.sweep() == 1
      assert {:ok, _} = Quizzes.fetch(quiz.id)
      assert Repo.aggregate(from(q in Quizzes.Quiz, where: q.id == ^quiz.id), :count) == 1
    end
  end
end

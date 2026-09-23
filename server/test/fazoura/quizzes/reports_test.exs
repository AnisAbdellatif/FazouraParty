defmodule Fazoura.Quizzes.ReportsTest do
  use Fazoura.DataCase, async: false

  alias Fazoura.QuizFixtures
  alias Fazoura.Quizzes
  alias Fazoura.Quizzes.Reports

  defp key(letter), do: "k-" <> String.duplicate(letter, 40)

  defp report(quiz, letter, params), do: Reports.submit(quiz.id, key(letter), params)

  describe "submitting" do
    test "records a report against a published quiz" do
      quiz = QuizFixtures.published!(%{"title" => "Bad Night"})

      assert {:ok, recorded} = report(quiz, "a", %{"reason" => "hate", "note" => "Question 3."})

      assert recorded.reason == "hate"
      assert recorded.note == "Question 3."
      assert recorded.status == "open"
      assert recorded.quiz_id == quiz.id
    end

    test "an empty note is no note, not a blank one" do
      quiz = QuizFixtures.published!()

      assert {:ok, recorded} = report(quiz, "a", %{"reason" => "spam", "note" => "   "})
      assert recorded.note == nil
    end

    test "refuses a reason nobody offered" do
      quiz = QuizFixtures.published!()

      assert {:error, :invalid_report} = report(quiz, "a", %{"reason" => "i-dislike-it"})
      assert Reports.open() == []
    end

    test "a quiz that does not exist cannot be reported" do
      assert {:error, :quiz_not_found} =
               Reports.submit(Ecto.UUID.generate(), key("a"), %{"reason" => "spam"})
    end

    test "needs a key, so a report counts a device rather than a tap" do
      quiz = QuizFixtures.published!()

      assert {:error, :owner_key_required} =
               Reports.submit(quiz.id, nil, %{"reason" => "spam"})
    end
  end

  describe "one device, one report" do
    test "reporting twice rewords it rather than counting twice" do
      quiz = QuizFixtures.published!()

      {:ok, first} = report(quiz, "a", %{"reason" => "spam", "note" => "Nonsense"})
      {:ok, second} = report(quiz, "a", %{"reason" => "hate", "note" => "Worse than that"})

      assert second.id == first.id
      assert [queued] = Reports.open()
      assert queued.count == 1
      assert [only] = queued.reports
      assert only.reason == "hate"
      assert only.note == "Worse than that"
    end

    test "but the clock keeps running from the first one" do
      quiz = QuizFixtures.published!()

      {:ok, first} = report(quiz, "a", %{"reason" => "spam"})
      {:ok, second} = report(quiz, "a", %{"reason" => "hate"})

      assert second.reported_at == first.reported_at
    end

    test "re-reporting cannot undo a decision" do
      quiz = QuizFixtures.published!()
      {:ok, _} = report(quiz, "a", %{"reason" => "spam"})
      {:ok, 1} = Reports.dismiss(quiz.id)

      {:ok, again} = report(quiz, "a", %{"reason" => "hate"})

      assert again.status == "dismissed"
      assert Reports.open() == []
    end

    test "another device is another voice" do
      quiz = QuizFixtures.published!()

      {:ok, _} = report(quiz, "a", %{"reason" => "spam"})
      {:ok, _} = report(quiz, "b", %{"reason" => "hate"})

      assert [queued] = Reports.open()
      assert queued.count == 2
    end
  end

  describe "the queue" do
    test "groups by quiz, longest-waiting first" do
      old = QuizFixtures.published!(%{"title" => "Older"})
      recent = QuizFixtures.published!(%{"title" => "Newer"})

      {:ok, _} = report(old, "a", %{"reason" => "spam"})
      {:ok, _} = report(recent, "b", %{"reason" => "hate"})
      # A second voice on the newer quiz must not push it ahead of the one
      # that has been waiting longer.
      {:ok, _} = report(recent, "c", %{"reason" => "hate"})

      assert [first, second] = Reports.open()
      assert first.quiz.title == "Older"
      assert first.count == 1
      assert second.quiz.title == "Newer"
      assert second.count == 2
    end

    test "counts quizzes waiting, not reports" do
      quiz = QuizFixtures.published!()
      {:ok, _} = report(quiz, "a", %{"reason" => "spam"})
      {:ok, _} = report(quiz, "b", %{"reason" => "hate"})

      assert Reports.open_count() == 1
    end

    test "is empty until somebody reports something" do
      QuizFixtures.published!()

      assert Reports.open() == []
      assert Reports.open_count() == 0
    end

    test "carries the quiz, so an admin can read it without a second query" do
      quiz = QuizFixtures.published!(%{"title" => "Readable"})
      {:ok, _} = report(quiz, "a", %{"reason" => "spam"})

      assert [queued] = Reports.open()
      assert queued.quiz.title == "Readable"
      assert [_ | _] = queued.quiz.questions
    end
  end

  describe "answering" do
    test "keeping the quiz clears its reports and leaves it public" do
      quiz = QuizFixtures.published!()
      {:ok, _} = report(quiz, "a", %{"reason" => "spam"})
      {:ok, _} = report(quiz, "b", %{"reason" => "hate"})

      assert {:ok, 2} = Reports.dismiss(quiz.id)

      assert Reports.open() == []
      assert {:ok, _still_there} = Quizzes.fetch(quiz.id)
    end

    test "taking the quiz down takes its reports with it" do
      quiz = QuizFixtures.published!()
      {:ok, _} = report(quiz, "a", %{"reason" => "spam"})

      assert {:ok, _} = Fazoura.Admin.delete_quiz(quiz.id)

      assert Reports.open() == []
      assert Reports.open_count() == 0
    end

    test "a quiz that is already gone cannot be answered" do
      assert {:error, :quiz_not_found} = Reports.dismiss(Ecto.UUID.generate())
    end
  end
end

defmodule Fazoura.Quizzes.ReviewTest do
  use Fazoura.DataCase, async: false

  alias Fazoura.{QuizFixtures, Quizzes}
  alias Fazoura.Quizzes.{Archive, Review}

  @owner QuizFixtures.owner_key()
  @other QuizFixtures.other_key()

  defp package(attrs \\ %{}) do
    document = QuizFixtures.quiz_params(attrs) |> Map.put("format_version", 1)
    {:ok, binary} = Archive.build(atomise(document), %{})
    binary
  end

  # Archive.build/2 takes the document in the shape `to_document/2` produces.
  defp atomise(map) when is_map(map),
    do: Map.new(map, fn {k, v} -> {String.to_atom(k), atomise(v)} end)

  defp atomise(list) when is_list(list), do: Enum.map(list, &atomise/1)
  defp atomise(other), do: other

  describe "submitting" do
    test "queues the package and nothing else" do
      assert {:ok, submission} = Review.submit(package(), @owner)

      assert submission.status == "pending"
      assert submission.title == "Movie Night"
      assert submission.question_count == 1
      assert submission.submitted_at

      # The point of the whole thing: nothing is public, and nothing is a quiz.
      assert {:ok, [], nil} = Quizzes.list()
      assert Repo.aggregate(Quizzes.Quiz, :count) == 0
    end

    test "needs a publisher key" do
      assert Review.submit(package(), nil) == {:error, :owner_key_required}
      assert Review.submit(package(), "short") == {:error, :owner_key_required}
    end

    test "refuses something that is not a package" do
      assert {:error, _} = Review.submit("not a zip at all", @owner)
    end

    test "refuses a package with no title or no questions" do
      assert Review.submit(package(%{"questions" => []}), @owner) == {:error, :invalid_quiz}
      assert Review.submit(package(%{"title" => "   "}), @owner) == {:error, :invalid_quiz}
    end
  end

  describe "the queue" do
    test "is oldest first, and counted" do
      {:ok, first} = Review.submit(package(%{"title" => "First"}), @owner)
      {:ok, second} = Review.submit(package(%{"title" => "Second"}), @other)

      assert Review.pending_count() == 2
      assert Enum.map(Review.pending(), & &1.id) == [first.id, second.id]

      {:ok, _quiz} = Review.approve(first.id)
      assert Review.pending_count() == 1
      assert Enum.map(Review.pending(), & &1.id) == [second.id]
    end

    test "a device sees only what it sent" do
      {:ok, mine} = Review.submit(package(%{"title" => "Mine"}), @owner)
      {:ok, _theirs} = Review.submit(package(%{"title" => "Theirs"}), @other)

      assert Enum.map(Review.for_owner(@owner), & &1.id) == [mine.id]
    end
  end

  describe "approving" do
    test "publishes the quiz, and only then does it exist" do
      {:ok, submission} = Review.submit(package(), @owner)

      assert {:ok, quiz} = Review.approve(submission.id)
      assert quiz.visibility == "public"
      assert quiz.title == "Movie Night"

      # Owned by the device that sent it, so it can still edit or unpublish it.
      assert Quizzes.owner?(quiz, @owner)

      {:ok, listed, _} = Quizzes.list()
      assert Enum.map(listed, & &1.title) == ["Movie Night"]

      assert {:ok, reloaded} = Review.fetch(submission.id)
      assert reloaded.status == "approved"
      assert reloaded.quiz_id == quiz.id
      # The quiz carries the content now; a second copy of every photo would be
      # disk for nothing.
      assert reloaded.package == <<>>
    end
  end

  describe "rejecting" do
    test "keeps the reason and drops the package" do
      {:ok, submission} = Review.submit(package(), @owner)

      assert {:ok, rejected} = Review.reject(submission.id, "Question 2 is not suitable.")
      assert rejected.status == "rejected"
      assert rejected.review_note == "Question 2 is not suitable."
      assert rejected.package == <<>>

      assert Review.pending_count() == 0
      assert Repo.aggregate(Quizzes.Quiz, :count) == 0
    end
  end

  describe "withdrawing" do
    test "the device that sent it may, and nobody else" do
      {:ok, submission} = Review.submit(package(), @owner)

      assert Review.withdraw(submission.id, @other) == {:error, :not_found}
      assert {:ok, _still_there} = Review.fetch(submission.id)

      assert Review.withdraw(submission.id, @owner) == :ok
      assert Review.fetch(submission.id) == {:error, :not_found}
    end
  end
end

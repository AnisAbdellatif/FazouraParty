defmodule Fazoura.Quizzes.VersionFormatTest do
  @moduledoc """
  The two quiz version numbers (QUIZ_FORMAT.md §2.1), and the documents written
  before they swapped shapes.

  `format_version` is a contract and carries a minor; a quiz's own `version` is
  a revision counter and is a plain integer. Every preset in `priv/quizzes`,
  every package in `priv/packages` and every quiz saved on somebody's device
  predates that, so reading the old shapes is not a nicety.
  """

  use Fazoura.DataCase, async: false

  alias Fazoura.QuizFixtures
  alias Fazoura.Quizzes
  alias Fazoura.Quizzes.Quiz

  defp create(params),
    do: Quizzes.create(QuizFixtures.quiz_params(params), QuizFixtures.owner_key())

  describe "format_version" do
    test "a document from before the minor existed is format 1.0" do
      assert {:ok, quiz} = create(%{"format_version" => 1})
      assert quiz.format_version == "1.0"
    end

    test "a document that names the format is taken at its word" do
      assert {:ok, quiz} = create(%{"format_version" => "1.0"})
      assert quiz.format_version == "1.0"
    end

    test "a later minor of the same major is readable" do
      # The point of the minor: 1.1 can only have added keys, and an unknown key
      # is ignored. Refusing it would make every quiz unreadable the moment the
      # format grew, including on servers that had not been updated yet.
      assert {:ok, quiz} = create(%{"format_version" => "1.7"})
      # Stored as the format it was actually read as, not as what it claimed.
      assert quiz.format_version == Quiz.format_version()
    end

    test "another major is not" do
      assert {:error, changeset} = create(%{"format_version" => "2.0"})
      assert %{format_version: [message]} = errors_on(changeset)
      assert message =~ "reads 1.0"
    end

    test "and neither is an old-style integer from another major" do
      assert {:error, changeset} = create(%{"format_version" => 2})
      assert %{format_version: [_message]} = errors_on(changeset)
    end
  end

  describe "a quiz's own version" do
    test "starts at one and counts up as it is replaced" do
      {:ok, quiz} = create(%{})
      assert quiz.version == 1

      {:ok, quiz} = Quizzes.replace_document(quiz, QuizFixtures.quiz_params(%{"title" => "Two"}))
      assert quiz.version == 2

      {:ok, quiz} =
        Quizzes.replace_document(quiz, QuizFixtures.quiz_params(%{"title" => "Three"}))

      assert quiz.version == 3
    end

    test "an old <major>.<minor> revision keeps its place in the count" do
      # "1.0" was the first revision and "1.4" the fifth, so a device that saved
      # the fifth must not find the server claiming to be on the first.
      assert {:ok, quiz} = create(%{"version" => "1.4"})
      assert quiz.version == 5

      assert {:ok, first} = create(%{"version" => "1.0", "title" => "Fresh"})
      assert first.version == 1
    end

    test "nonsense counts as the first revision rather than failing" do
      # It is a counter, not a contract: a document with a version nobody can
      # read is still a perfectly good quiz.
      for version <- ["", "banana", "1.x", nil] do
        assert {:ok, quiz} = create(%{"version" => version, "title" => "V #{inspect(version)}"})
        assert quiz.version == 1
      end
    end

    test "zero and below are refused" do
      assert {:error, changeset} = create(%{"version" => 0})
      assert %{version: [_message]} = errors_on(changeset)
    end
  end

  describe "what a client is handed" do
    test "carries both numbers in their new shapes" do
      {:ok, quiz} = create(%{})

      {:ok, quiz} =
        Quizzes.replace_document(quiz, QuizFixtures.quiz_params(%{"title" => "Again"}))

      document = Quizzes.to_document(quiz)

      assert document.format_version == "1.0"
      assert document.version == 2
    end
  end
end

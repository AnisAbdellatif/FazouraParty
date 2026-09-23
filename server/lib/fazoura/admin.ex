defmodule Fazoura.Admin do
  @moduledoc """
  What the admin dashboard reads and changes (protocol/ADMIN.md).

  Moderation lives here rather than in `Fazoura.Quizzes` because it deliberately ignores
  the publisher key: an admin may delete or promote anything.
  """

  import Ecto.Query

  alias Fazoura.Metrics
  alias Fazoura.Quizzes
  alias Fazoura.Quizzes.{Image, Question, Quiz, Reports, Review, Tag}
  alias Fazoura.Repo
  alias Fazoura.Rooms

  ## Stats

  @doc "Everything the stats tab shows: live rooms now, counters, library totals."
  @spec stats() :: map()
  def stats do
    rooms = Rooms.active()

    %{
      rooms: rooms,
      live_rooms: length(rooms),
      live_connections: Enum.sum(Enum.map(rooms, & &1.connections)),
      live_players: Enum.sum(Enum.map(rooms, & &1.players)),
      by_phase: Enum.frequencies_by(rooms, & &1.phase),
      rooms_created: Metrics.get(:rooms_created),
      library: library_counts(),
      top_tags: Quizzes.popular_tags(8),
      recent: recent_quizzes(5)
    }
  end

  defp library_counts do
    %{
      quizzes: Repo.aggregate(Quiz, :count),
      presets: Repo.aggregate(from(q in Quiz, where: q.source == "builtin"), :count),
      community: Repo.aggregate(from(q in Quiz, where: q.source == "custom"), :count),
      questions: Repo.aggregate(Question, :count),
      photo_questions:
        Repo.aggregate(from(q in Question, where: not is_nil(q.image_key)), :count),
      images: Repo.aggregate(Image, :count),
      tags: Repo.one(from(t in Tag, select: count(t.tag, :distinct))) || 0
    }
  end

  defp recent_quizzes(limit) do
    Repo.all(
      from q in Quiz,
        order_by: [desc: q.inserted_at, asc: q.id],
        limit: ^limit,
        preload: [:quiz_tags]
    )
  end

  ## Quiz moderation

  @doc "Stored quizzes for the quizzes tab, newest first. `:q` matches title or tag."
  @spec list_quizzes(keyword()) :: [Quiz.t()]
  def list_quizzes(opts \\ []) do
    limit = opts |> Keyword.get(:limit, 50) |> max(1) |> min(200)

    from(q in Quiz, order_by: [desc: q.updated_at, asc: q.id], limit: ^limit)
    |> search(opts[:q])
    |> preload([:quiz_tags])
    |> Repo.all()
  end

  defp search(query, text) when is_binary(text) do
    case text |> String.replace(~r/[%_\\]/, "") |> String.trim() |> String.downcase() do
      "" ->
        query

      term ->
        pattern = "%#{term}%"

        where(
          query,
          [q],
          like(fragment("lower(?)", q.title), ^pattern) or
            fragment(
              "EXISTS (SELECT 1 FROM quiz_tags qt WHERE qt.quiz_id = ? AND qt.tag LIKE ?)",
              q.id,
              ^pattern
            )
        )
    end
  end

  defp search(query, _text), do: query

  @doc "Deletes any quiz — preset or community — and its questions and tags."
  @spec delete_quiz(term()) :: {:ok, Quiz.t()} | {:error, :quiz_not_found}
  def delete_quiz(id) do
    with {:ok, quiz} <- fetch(id) do
      Repo.delete(quiz)
    end
  end

  @doc """
  Makes a community quiz a preset (hostable by slug, shown first when browsing) or turns
  one back into an ordinary public quiz.
  """
  @spec set_preset(term(), boolean()) :: {:ok, Quiz.t()} | {:error, :quiz_not_found}
  def set_preset(id, preset?) do
    with {:ok, quiz} <- fetch(id) do
      changes =
        if preset?,
          do: %{source: "builtin", slug: quiz.slug || unique_slug(quiz.title)},
          else: %{source: "custom", slug: nil}

      quiz |> Ecto.Changeset.change(changes) |> Repo.update()
    end
  end

  @doc """
  Creates a preset from a quiz document (QUIZ_FORMAT.md §2), the same JSON the apps and
  `priv/quizzes/*.json` use. Unlike publishing, no publisher key is involved and photo
  keys are trusted.
  """
  @spec create_preset(String.t() | map()) ::
          {:ok, Quiz.t()} | {:error, Ecto.Changeset.t() | :invalid_json}
  def create_preset(json) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, %{} = params} -> create_preset(params)
      _ -> {:error, :invalid_json}
    end
  end

  def create_preset(%{} = params) do
    title = if is_binary(params["title"]), do: params["title"], else: "preset"

    %Quiz{
      source: "builtin",
      visibility: "public",
      slug: unique_slug(title),
      questions: [],
      quiz_tags: []
    }
    |> Quiz.changeset(params)
    |> Repo.insert()
  end

  @doc """
  Creates a preset from an uploaded `.fazoura` package (QUIZ_FORMAT.md §5.3b).

  The same thing as `create_preset/1`, except that the photos travel with the document
  instead of having been uploaded first: they are stored on the way in and the questions
  end up pointing at ordinary uploads.
  """
  @spec create_preset_from_package(binary()) ::
          {:ok, Quiz.t()} | {:error, Ecto.Changeset.t() | atom() | {atom(), String.t()}}
  def create_preset_from_package(binary) do
    with {:ok, params} <- Quizzes.read_archive(binary), do: create_preset(params)
  end

  @doc """
  The quiz the editor works on, with its questions and tags (ADMIN.md §3.5).
  """
  @spec fetch_quiz(term()) :: {:ok, Quiz.t()} | {:error, :quiz_not_found}
  def fetch_quiz(id) do
    with {:ok, quiz} <- fetch(id) do
      {:ok, Repo.preload(quiz, [:questions, :quiz_tags])}
    end
  end

  @doc """
  Replaces a quiz from an edited document (QUIZ_FORMAT.md §2).

  Moderation, so no publisher key is involved and photo keys are trusted — the editor
  only ever sets one it has just stored. Questions are re-issued, as they are on any
  replacement, and the minor version is bumped.
  """
  @spec update_quiz(term(), map()) ::
          {:ok, Quiz.t()} | {:error, Ecto.Changeset.t() | :quiz_not_found}
  def update_quiz(id, params) do
    with {:ok, quiz} <- fetch_quiz(id) do
      Quizzes.replace_document(quiz, params)
    end
  end

  @doc """
  A changeset's errors as one line: "title can't be blank · tags must be a list of 1 to
  10 tags". The dashboard has nowhere better to put them than a flash.
  """
  @spec error_messages(Ecto.Changeset.t()) :: String.t()
  def error_messages(%Ecto.Changeset{} = changeset) do
    changeset
    |> Ecto.Changeset.traverse_errors(fn {message, _opts} -> message end)
    |> Enum.map_join(" · ", fn {field, messages} ->
      "#{field} #{messages |> List.flatten() |> flatten_messages()}"
    end)
  end

  # Question errors arrive as a list of per-question maps, most of them empty.
  defp flatten_messages(messages) do
    messages
    |> Enum.flat_map(fn
      message when is_binary(message) ->
        [message]

      %{} = nested ->
        Enum.map(nested, fn {field, list} -> "#{field} #{Enum.join(list, ", ")}" end)
    end)
    |> Enum.uniq()
    |> Enum.join(", ")
  end

  # Anything that isn't a uuid is "not found" rather than a cast error.
  defp fetch(id) when is_binary(id) do
    with {:ok, uuid} <- Ecto.UUID.cast(id),
         %Quiz{} = quiz <- Repo.get(Quiz, uuid) do
      {:ok, quiz}
    else
      _ -> {:error, :quiz_not_found}
    end
  end

  defp fetch(_id), do: {:error, :quiz_not_found}

  # "Movie Night!" -> "movie-night", with -2, -3… when that slug is taken.
  defp unique_slug(title) do
    base =
      title
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/u, "-")
      |> String.trim("-")
      |> String.slice(0, 60)

    base = if base == "", do: "preset", else: base

    Enum.find_value(Stream.iterate(1, &(&1 + 1)), fn
      1 -> unless taken?(base), do: base
      n -> unless taken?("#{base}-#{n}"), do: "#{base}-#{n}"
    end)
  end

  defp taken?(slug), do: Repo.exists?(from q in Quiz, where: q.slug == ^slug)

  ## The review queue (ADMIN.md §3.2)

  @doc "Submissions waiting to be read, oldest first."
  defdelegate pending_submissions(limit \\ 50), to: Review, as: :pending

  @doc "How many are waiting."
  defdelegate pending_submission_count(), to: Review, as: :pending_count

  @doc "One submission."
  defdelegate fetch_submission(id), to: Review, as: :fetch

  @doc "What is inside a submission's package, for somebody to read before deciding."
  defdelegate submission_contents(submission), to: Review, as: :contents

  @doc "Publishes a submission. Its photos reach the uploads volume here and not before."
  defdelegate approve_submission(id), to: Review, as: :approve

  @doc "Turns a submission down, with a note its author's device can show."
  defdelegate reject_submission(id, note), to: Review, as: :reject

  ## Reported quizzes (ADMIN.md §3.3)

  @doc "Published quizzes somebody has objected to, longest-waiting first."
  defdelegate reported_quizzes(limit \\ 50), to: Reports, as: :open

  @doc "How many quizzes are waiting on an answer."
  defdelegate reported_quiz_count(), to: Reports, as: :open_count

  @doc """
  Answers every open report against a quiz without taking it down.

  The other answer is `delete_quiz/1`, which takes the quiz's reports with it.
  """
  defdelegate dismiss_reports(quiz_id), to: Reports, as: :dismiss
end

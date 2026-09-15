defmodule Fazoura.Quizzes do
  @moduledoc """
  Quizzes: the content rooms play (protocol/QUIZ_FORMAT.md).

  Stored with Ecto, exchanged as JSON documents. Until accounts exist, a per-device
  owner key owns custom quizzes; private quizzes are only visible to that key.
  """

  import Ecto.Query

  alias Fazoura.Game.Pack
  alias Fazoura.Quizzes.{Image, OwnerKey, Question, Quiz}
  alias Fazoura.Repo
  alias Fazoura.Uploads

  @uuid ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

  @type owner_key :: String.t() | nil

  ## Listing and reading

  @doc """
  Lists quiz summaries. Options: `:scope` ("public" | "mine"), `:owner_key`, `:q`,
  `:category`, `:limit` (1–50), `:offset`. Returns the page and the next offset.
  """
  @spec list(keyword()) ::
          {:ok, [Quiz.t()], non_neg_integer() | nil}
          | {:error, :owner_key_required | :invalid_scope}
  def list(opts \\ []) do
    limit = opts |> Keyword.get(:limit, 20) |> max(1) |> min(50)
    offset = opts |> Keyword.get(:offset, 0) |> max(0)

    with {:ok, query} <- scope_query(Keyword.get(opts, :scope, "public"), opts[:owner_key]) do
      rows =
        query
        |> search(opts[:q])
        |> in_category(opts[:category])
        |> order_by([q],
          asc: fragment("CASE WHEN ? = 'builtin' THEN 0 ELSE 1 END", q.source),
          desc: q.updated_at,
          asc: q.id
        )
        |> limit(^(limit + 1))
        |> offset(^offset)
        |> Repo.all()

      {page, rest} = Enum.split(rows, limit)
      {:ok, page, if(rest == [], do: nil, else: offset + limit)}
    end
  end

  defp scope_query("public", _key), do: {:ok, from(q in Quiz, where: q.visibility == "public")}

  defp scope_query("mine", key) do
    case OwnerKey.hash(key) do
      {:ok, hash} -> {:ok, from(q in Quiz, where: q.owner_key_hash == ^hash)}
      :error -> {:error, :owner_key_required}
    end
  end

  defp scope_query(_scope, _key), do: {:error, :invalid_scope}

  defp search(query, text) when is_binary(text) do
    case text |> String.replace(~r/[%_\\]/, "") |> String.trim() |> String.downcase() do
      "" -> query
      term -> where(query, [q], like(fragment("lower(?)", q.title), ^"%#{term}%"))
    end
  end

  defp search(query, _text), do: query

  defp in_category(query, category) when is_binary(category) and category != "",
    do: where(query, [q], q.category == ^category)

  defp in_category(query, _category), do: query

  @doc "A quiz (with questions) the caller may see, by uuid or built-in slug."
  @spec fetch_visible(term(), owner_key()) :: {:ok, Quiz.t()} | {:error, :quiz_not_found}
  def fetch_visible(id, owner_key) do
    with {:ok, quiz} <- get(id),
         true <- quiz.visibility == "public" or owner?(quiz, owner_key) do
      {:ok, quiz}
    else
      _ -> {:error, :quiz_not_found}
    end
  end

  @spec owner?(Quiz.t(), owner_key()) :: boolean()
  def owner?(%Quiz{owner_key_hash: nil}, _key), do: false
  def owner?(%Quiz{owner_key_hash: hash}, key), do: OwnerKey.hash(key) == {:ok, hash}

  defp get(id) when is_binary(id) do
    query =
      if id =~ @uuid,
        do: from(q in Quiz, where: q.id == ^String.downcase(id)),
        else: from(q in Quiz, where: q.slug == ^id)

    case Repo.one(query) do
      nil -> {:error, :quiz_not_found}
      quiz -> {:ok, Repo.preload(quiz, :questions)}
    end
  end

  defp get(_id), do: {:error, :quiz_not_found}

  defp fetch_owned(id, owner_key) do
    with {:ok, quiz} <- get(id),
         true <- owner?(quiz, owner_key) do
      {:ok, quiz}
    else
      _ -> {:error, :quiz_not_found}
    end
  end

  ## Writing

  @spec create(map(), owner_key()) ::
          {:ok, Quiz.t()}
          | {:error, Ecto.Changeset.t() | :owner_key_required | :unknown_image}
  def create(params, owner_key) do
    with {:ok, hash} <- require_owner_key(owner_key),
         :ok <- check_images(params, hash) do
      %Quiz{source: "custom", owner_key_hash: hash, questions: []}
      |> Quiz.changeset(params)
      |> Repo.insert()
    end
  end

  @doc "Replaces a custom quiz and all its questions. Owner only."
  @spec replace(term(), map(), owner_key()) ::
          {:ok, Quiz.t()}
          | {:error, Ecto.Changeset.t() | :quiz_not_found | :unknown_image}
  def replace(id, params, owner_key) do
    with {:ok, quiz} <- fetch_owned(id, owner_key),
         :ok <- check_images(params, quiz.owner_key_hash) do
      Repo.transaction(fn -> replace_questions!(quiz, params) end)
    end
  end

  # Old questions are deleted first so the new ones can reuse their positions.
  defp replace_questions!(quiz, params) do
    Repo.delete_all(from(q in Question, where: q.quiz_id == ^quiz.id))

    case %{quiz | questions: []} |> Quiz.changeset(params) |> Repo.update() do
      {:ok, updated} -> updated
      {:error, changeset} -> Repo.rollback(changeset)
    end
  end

  @spec set_visibility(term(), term(), owner_key()) ::
          {:ok, Quiz.t()} | {:error, Ecto.Changeset.t() | :quiz_not_found}
  def set_visibility(id, visibility, owner_key) do
    with {:ok, quiz} <- fetch_owned(id, owner_key) do
      quiz |> Quiz.visibility_changeset(visibility) |> Repo.update()
    end
  end

  @spec delete(term(), owner_key()) :: :ok | {:error, :quiz_not_found}
  def delete(id, owner_key) do
    with {:ok, quiz} <- fetch_owned(id, owner_key),
         {:ok, _deleted} <- Repo.delete(quiz) do
      :ok
    end
  end

  defp require_owner_key(key) do
    case OwnerKey.hash(key) do
      {:ok, hash} -> {:ok, hash}
      :error -> {:error, :owner_key_required}
    end
  end

  # Photo questions may only use images uploaded with the same owner key.
  defp check_images(%{"questions" => questions}, hash) when is_list(questions) do
    keys =
      for %{"image" => %{"key" => key}} <- questions, is_binary(key), uniq: true, do: key

    known =
      Repo.aggregate(
        from(i in Image, where: i.key in ^keys and i.owner_key_hash == ^hash),
        :count
      )

    if known == length(keys), do: :ok, else: {:error, :unknown_image}
  end

  defp check_images(_params, _hash), do: :ok

  ## Images

  @spec store_image(binary(), owner_key()) ::
          {:ok, Image.t()}
          | {:error, :owner_key_required | :image_too_large | :unsupported_image}
  def store_image(binary, owner_key) do
    with {:ok, hash} <- require_owner_key(owner_key),
         {:ok, stored} <- Uploads.store(binary) do
      Repo.insert(%Image{
        key: stored.key,
        content_type: stored.content_type,
        byte_size: stored.byte_size,
        owner_key_hash: hash
      })
    end
  end

  ## Documents (JSON shape, QUIZ_FORMAT.md §2)

  @doc """
  The quiz as a JSON document. Questions (and their accepted answers) are included only
  for the owner, and only when `questions: true` (default).
  """
  @spec to_document(Quiz.t(), keyword()) :: map()
  def to_document(%Quiz{} = quiz, opts \\ []) do
    owner? = Keyword.get(opts, :owner?, false)

    document = %{
      format_version: quiz.format_version,
      id: quiz.id,
      slug: quiz.slug,
      title: quiz.title,
      description: quiz.description,
      language: quiz.language,
      category: quiz.category,
      tags: quiz.tags,
      source: quiz.source,
      visibility: quiz.visibility,
      is_owner: owner?,
      default_settings: %{
        time_limit_ms: quiz.default_time_limit_ms,
        difficulty_multiplier: quiz.default_difficulty_multiplier
      },
      question_count: quiz.question_count,
      has_photos: quiz.has_photos,
      created_at: quiz.inserted_at,
      updated_at: quiz.updated_at
    }

    if owner? and Keyword.get(opts, :questions, true),
      do: Map.put(document, :questions, Enum.map(quiz.questions, &question_document/1)),
      else: document
  end

  defp question_document(%Question{} = question) do
    %{
      id: question.id,
      type: question.type,
      prompt: question.prompt,
      accepted_answers: question.accepted_answers,
      difficulty: question.difficulty,
      time_limit_ms: question.time_limit_ms,
      image:
        question.image_key &&
          %{
            key: question.image_key,
            url: Uploads.url(question.image_key),
            alt: question.image_alt
          },
      explanation: question.explanation
    }
  end

  @doc "Immutable snapshot a room plays (PROTOCOL.md §6.2)."
  @spec to_pack(Quiz.t()) :: Pack.t()
  def to_pack(%Quiz{} = quiz) do
    %Pack{
      id: quiz.id,
      title: quiz.title,
      default_time_limit_ms: quiz.default_time_limit_ms,
      default_difficulty_multiplier: quiz.default_difficulty_multiplier,
      questions:
        Enum.map(quiz.questions, fn question ->
          %Pack.Question{
            id: question.id,
            type: question.type,
            prompt: question.prompt,
            accepted_answers: question.accepted_answers,
            time_limit_ms: question.time_limit_ms || quiz.default_time_limit_ms,
            image_url: question.image_key && Uploads.url(question.image_key),
            difficulty: question.difficulty
          }
        end)
    }
  end

  ## Built-in quizzes

  @doc """
  Upserts every `priv/quizzes/<slug>.json` document as a public built-in quiz.
  Idempotent; run by `priv/repo/seeds.exs`.
  """
  @spec sync_builtin!(String.t()) :: [Quiz.t()]
  def sync_builtin!(dir \\ Path.join(:code.priv_dir(:fazoura), "quizzes")) do
    for path <- dir |> Path.join("*.json") |> Path.wildcard() |> Enum.sort() do
      slug = Path.basename(path, ".json")
      params = path |> File.read!() |> Jason.decode!() |> Map.put("visibility", "public")

      {:ok, quiz} = Repo.transaction(fn -> upsert_builtin!(slug, params) end)
      quiz
    end
  end

  defp upsert_builtin!(slug, params) do
    quiz =
      case Repo.get_by(Quiz, slug: slug) do
        nil ->
          %Quiz{slug: slug, source: "builtin", questions: []}

        existing ->
          Repo.delete_all(from(q in Question, where: q.quiz_id == ^existing.id))
          %{existing | questions: []}
      end

    quiz |> Quiz.changeset(params) |> Repo.insert_or_update!()
  end
end

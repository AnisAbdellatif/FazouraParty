defmodule Fazoura.Quizzes do
  @moduledoc """
  Quizzes: the content rooms play (protocol/QUIZ_FORMAT.md).

  There are no accounts. The database only holds public quizzes (built-in and
  published ones); a per-device publisher key lets the device that published a quiz
  update or unpublish it. Private quizzes never reach the database: the app keeps them
  and sends the whole document each time it hosts (`inline_pack/1`).
  """

  import Ecto.Query

  alias Fazoura.Game.Pack
  alias Fazoura.Quizzes.{Image, OwnerKey, Question, Quiz}
  alias Fazoura.Repo
  alias Fazoura.Rooms.Images
  alias Fazoura.Uploads

  @uuid ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

  @type owner_key :: String.t() | nil

  ## Listing and reading

  @doc """
  Lists public quiz summaries. Options: `:q`, `:category`, `:limit` (1–50), `:offset`.
  Returns the page and the next offset.
  """
  @spec list(keyword()) :: {:ok, [Quiz.t()], non_neg_integer() | nil}
  def list(opts \\ []) do
    limit = opts |> Keyword.get(:limit, 20) |> max(1) |> min(50)
    offset = opts |> Keyword.get(:offset, 0) |> max(0)

    rows =
      from(q in Quiz, where: q.visibility == "public")
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

  @doc "A stored quiz with its questions, by uuid or built-in slug."
  @spec fetch(term()) :: {:ok, Quiz.t()} | {:error, :quiz_not_found}
  def fetch(id) when is_binary(id) do
    query =
      if id =~ @uuid,
        do: from(q in Quiz, where: q.id == ^String.downcase(id)),
        else: from(q in Quiz, where: q.slug == ^id)

    case Repo.one(query) do
      nil -> {:error, :quiz_not_found}
      quiz -> {:ok, Repo.preload(quiz, :questions)}
    end
  end

  def fetch(_id), do: {:error, :quiz_not_found}

  @doc "Whether `key` is the publisher key the quiz was published with."
  @spec owner?(Quiz.t(), owner_key()) :: boolean()
  def owner?(%Quiz{owner_key_hash: nil}, _key), do: false
  def owner?(%Quiz{owner_key_hash: hash}, key), do: OwnerKey.hash(key) == {:ok, hash}

  defp fetch_owned(id, owner_key) do
    with {:ok, quiz} <- fetch(id),
         true <- owner?(quiz, owner_key) do
      {:ok, quiz}
    else
      _ -> {:error, :quiz_not_found}
    end
  end

  ## Publishing

  @doc "Publishes a quiz document. The publisher key may later update or unpublish it."
  @spec create(map(), owner_key()) ::
          {:ok, Quiz.t()}
          | {:error, Ecto.Changeset.t() | :owner_key_required | :unknown_image}
  def create(params, owner_key) do
    with {:ok, hash} <- require_owner_key(owner_key),
         :ok <- check_images(params, hash) do
      %Quiz{source: "custom", visibility: "public", owner_key_hash: hash, questions: []}
      |> Quiz.changeset(params)
      |> Repo.insert()
    end
  end

  @doc "Replaces a published quiz and all its questions. Publisher only."
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

  @doc "Unpublishes (deletes) a quiz. Publisher only."
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

  # Photo questions may only use images uploaded with the same publisher key.
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

  ## Private (inline) quizzes

  @doc """
  Validates a private quiz document sent with room creation (QUIZ_FORMAT.md §5.7) and
  builds its pack without touching the database. Photos come inline as base64
  `image.data`; they are kept in memory by `Fazoura.Rooms.Images` under the returned keys,
  which the caller attaches to the room (or deletes if the room can't start).
  """
  @spec inline_pack(term()) ::
          {:ok, Pack.t(), [String.t()]}
          | {:error, Ecto.Changeset.t() | :image_too_large | :unsupported_image}
  def inline_pack(params) do
    with {:ok, params, images} <- extract_inline_images(params),
         {:ok, quiz} <-
           %Quiz{source: "inline", visibility: "private", questions: []}
           |> Quiz.changeset(params)
           |> Ecto.Changeset.apply_action(:insert) do
      Images.put(images)
      {:ok, to_pack(quiz, &Images.url/1), Enum.map(images, &elem(&1, 0))}
    end
  end

  defp extract_inline_images(%{"questions" => questions} = params) when is_list(questions) do
    result =
      Enum.reduce_while(questions, {:ok, [], []}, fn question, {:ok, acc, images} ->
        case inline_image(question) do
          {:ok, question, nil} -> {:cont, {:ok, [question | acc], images}}
          {:ok, question, image} -> {:cont, {:ok, [question | acc], [image | images]}}
          error -> {:halt, error}
        end
      end)

    with {:ok, questions, images} <- result do
      {:ok, Map.put(params, "questions", Enum.reverse(questions)), Enum.reverse(images)}
    end
  end

  defp extract_inline_images(params), do: {:ok, params, []}

  # Stored image keys mean nothing for an inline quiz, so only `data` counts.
  defp inline_image(%{"image" => %{"data" => data} = image} = question) when is_binary(data) do
    with {:ok, binary} <- decode_image(data),
         {:ok, content_type, ext} <- detect_image(binary) do
      key = Images.new_key(ext)

      {:ok, Map.put(question, "image", %{"key" => key, "alt" => image["alt"]}),
       {key, content_type, binary}}
    end
  end

  defp inline_image(%{} = question), do: {:ok, Map.put(question, "image", nil), nil}
  defp inline_image(question), do: {:ok, question, nil}

  defp decode_image(data) do
    case Base.decode64(data, ignore: :whitespace) do
      {:ok, binary} when byte_size(binary) > 0 -> size_check(binary)
      _ -> {:error, :unsupported_image}
    end
  end

  defp size_check(binary) do
    if byte_size(binary) > Uploads.max_bytes(),
      do: {:error, :image_too_large},
      else: {:ok, binary}
  end

  defp detect_image(binary) do
    case Uploads.detect(binary) do
      {:ok, content_type, ext} -> {:ok, content_type, ext}
      :error -> {:error, :unsupported_image}
    end
  end

  ## Documents (JSON shape, QUIZ_FORMAT.md §2)

  @doc """
  The quiz as a JSON document. Questions (and their accepted answers) are included only
  for the publisher, and only when `questions: true` (default).
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

  @doc """
  Immutable snapshot a room plays (PROTOCOL.md §6.2). `image_url` turns an image key
  into the URL players load.
  """
  @spec to_pack(Quiz.t(), (String.t() -> String.t())) :: Pack.t()
  def to_pack(%Quiz{} = quiz, image_url \\ &Uploads.url/1) do
    %Pack{
      id: quiz.id || "inline",
      title: quiz.title,
      default_time_limit_ms: quiz.default_time_limit_ms,
      default_difficulty_multiplier: quiz.default_difficulty_multiplier,
      questions:
        Enum.map(quiz.questions, fn question ->
          %Pack.Question{
            id: question.id || "q#{question.position}",
            type: question.type,
            prompt: question.prompt,
            accepted_answers: question.accepted_answers,
            time_limit_ms: question.time_limit_ms || quiz.default_time_limit_ms,
            image_url: question.image_key && image_url.(question.image_key),
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
      params = path |> File.read!() |> Jason.decode!()

      {:ok, quiz} = Repo.transaction(fn -> upsert_builtin!(slug, params) end)
      quiz
    end
  end

  defp upsert_builtin!(slug, params) do
    quiz =
      case Repo.get_by(Quiz, slug: slug) do
        nil ->
          %Quiz{slug: slug, source: "builtin", visibility: "public", questions: []}

        existing ->
          Repo.delete_all(from(q in Question, where: q.quiz_id == ^existing.id))
          %{existing | questions: []}
      end

    quiz |> Quiz.changeset(params) |> Repo.insert_or_update!()
  end
end

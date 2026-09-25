defmodule Fazoura.Quizzes do
  @moduledoc """
  Quizzes: the content rooms play (protocol/QUIZ_FORMAT.md).

  There are no accounts. The database only holds public quizzes (built-in and
  published ones); a per-device publisher key lets the device that published a quiz
  update or unpublish it. Private quizzes never reach the database: the app keeps them
  and sends the whole document each time it hosts (`inline_pack/2`).
  """

  import Ecto.Query

  alias Fazoura.Game.Pack
  alias Fazoura.Quizzes.{Archive, Image, OwnerKey, Question, Quiz, Tag}
  alias Fazoura.Repo
  alias Fazoura.Rooms.Images
  alias Fazoura.Uploads

  @uuid ~r/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i

  # A private quiz's photos live in memory for as long as its room does, so the total
  # a single room can pin is capped as well as each photo (`Uploads.max_bytes/0`).
  # 8 MB is a 20-question quiz with a photo on every question at a realistic size,
  # while keeping a server's worth of rooms in the hundreds of MB rather than the GBs.
  @max_inline_bytes 8 * 1024 * 1024

  # Owns the photos that ship with the server. Not a secret and not held by any device:
  # it exists so preset photos have an owner like every other upload, while staying
  # outside the publish-and-edit path the apps use.
  @preset_owner_key "fazoura-preset-photos-owned-by-the-server"

  @type owner_key :: String.t() | nil

  @doc "Largest total of inline photo bytes one room may hold (QUIZ_FORMAT.md §5.7)."
  @spec max_inline_bytes() :: pos_integer()
  def max_inline_bytes,
    do: Application.get_env(:fazoura, :max_inline_bytes, @max_inline_bytes)

  ## Listing and reading

  @doc """
  Lists public quiz summaries. Options: `:q` (title or tag), `:tag` (exact tag),
  `:limit` (1–50), `:offset`. Returns the page and the next offset.
  """
  @spec list(keyword()) :: {:ok, [Quiz.t()], non_neg_integer() | nil}
  def list(opts \\ []) do
    limit = opts |> Keyword.get(:limit, 20) |> max(1) |> min(50)
    offset = opts |> Keyword.get(:offset, 0) |> max(0)

    rows =
      from(q in Quiz, where: q.visibility == "public", preload: [:quiz_tags])
      |> search(opts[:q])
      |> with_tag(opts[:tag])
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

  # Matches the title or any tag, so typing "movies" finds quizzes tagged with it.
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

  defp with_tag(query, tag) when is_binary(tag) do
    case Tag.normalize(tag) do
      "" ->
        query

      normalized ->
        where(
          query,
          [q],
          fragment(
            "EXISTS (SELECT 1 FROM quiz_tags qt WHERE qt.quiz_id = ? AND qt.tag = ?)",
            q.id,
            ^normalized
          )
        )
    end
  end

  defp with_tag(query, _tag), do: query

  @doc "Tags used by public quizzes, most used first, then alphabetically."
  @spec popular_tags(pos_integer()) :: [%{tag: String.t(), count: non_neg_integer()}]
  def popular_tags(limit \\ 30) do
    Repo.all(
      from t in Tag,
        join: q in Quiz,
        on: q.id == t.quiz_id and q.visibility == "public",
        group_by: t.tag,
        order_by: [desc: count(t.id), asc: t.tag],
        limit: ^(limit |> max(1) |> min(100)),
        select: %{tag: t.tag, count: count(t.id)}
    )
  end

  @doc "A stored quiz with its questions, by uuid or built-in slug."
  @spec fetch(term()) :: {:ok, Quiz.t()} | {:error, :quiz_not_found}
  def fetch(id) when is_binary(id) do
    query =
      if id =~ @uuid,
        do: from(q in Quiz, where: q.id == ^String.downcase(id)),
        else: from(q in Quiz, where: q.slug == ^id)

    case Repo.one(query) do
      nil -> {:error, :quiz_not_found}
      quiz -> {:ok, Repo.preload(quiz, [:questions, :quiz_tags])}
    end
  end

  def fetch(_id), do: {:error, :quiz_not_found}

  @doc "Whether `key` is the publisher key the quiz was published with."
  @spec owner?(Quiz.t(), owner_key()) :: boolean()
  def owner?(%Quiz{owner_key_hash: nil}, _key), do: false

  def owner?(%Quiz{owner_key_hash: hash}, key) do
    # Constant-time: both are hex SHA-256 digests, so a byte-by-byte `==` would leak,
    # through timing, how much of the stored hash a guess matched.
    case OwnerKey.hash(key) do
      {:ok, computed} -> Plug.Crypto.secure_compare(computed, hash)
      _ -> false
    end
  end

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
      %Quiz{
        source: "custom",
        visibility: "public",
        owner_key_hash: hash,
        questions: [],
        quiz_tags: []
      }
      |> Quiz.changeset(params)
      |> Repo.insert()
    end
  end

  @doc """
  Publishes a submission that has been read and accepted.

  The document has already come out of its package and its photos are already
  stored (`read_archive/1`), so this is the insert and nothing more. Only
  `Fazoura.Quizzes.Review` calls it: publishing straight from the API is what
  the queue exists to prevent (QUIZ_FORMAT.md §4).
  """
  @spec publish_reviewed(map(), String.t()) :: {:ok, Quiz.t()} | {:error, Ecto.Changeset.t()}
  def publish_reviewed(params, owner_key_hash) when is_binary(owner_key_hash) do
    %Quiz{
      source: "custom",
      visibility: "public",
      owner_key_hash: owner_key_hash,
      questions: [],
      quiz_tags: []
    }
    |> Quiz.changeset(params)
    |> Repo.insert()
  end

  @doc "Replaces a published quiz and all its questions. Publisher only."
  @spec replace(term(), map(), owner_key()) ::
          {:ok, Quiz.t()}
          | {:error, Ecto.Changeset.t() | :quiz_not_found | :unknown_image}
  def replace(id, params, owner_key) do
    with {:ok, quiz} <- fetch_owned(id, owner_key),
         :ok <- check_images(params, quiz.owner_key_hash) do
      replace_document(quiz, params)
    end
  end

  @doc """
  Replaces a quiz and all its children from a document, bumping its revision number so a
  device holding an offline copy can tell it is stale.

  Whoever calls this has already decided they are allowed to: `replace/3` checks the
  publisher key, and `Fazoura.Admin` answers to the dashboard instead (ADMIN.md §3.5).
  """
  @spec replace_document(Quiz.t(), map()) :: {:ok, Quiz.t()} | {:error, Ecto.Changeset.t()}
  def replace_document(%Quiz{} = quiz, params) do
    Repo.transaction(fn -> replace_children!(quiz, params) end)
  end

  # Old tags and questions are deleted first so the new ones can reuse their positions.
  defp replace_children!(quiz, params) do
    Repo.delete_all(from(q in Question, where: q.quiz_id == ^quiz.id))
    Repo.delete_all(from(t in Tag, where: t.quiz_id == ^quiz.id))

    params = Map.put(params, "version", increment_version(quiz.version))

    case %{quiz | questions: [], quiz_tags: []} |> Quiz.changeset(params) |> Repo.update() do
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

  @doc """
  Stores a photo the server itself owns, for one an admin adds from the dashboard.

  The same owner as a preset's photos: not a device's, so nothing published through the
  API can claim it and the photo cannot be removed by unpublishing something else.
  """
  @spec store_own_image(binary()) ::
          {:ok, Image.t()} | {:error, :image_too_large | :unsupported_image}
  def store_own_image(binary) do
    with {:ok, stored} <- Uploads.store_stable(binary), do: {:ok, register_photo(stored)}
  end

  @doc """
  Deletes uploaded photos nothing points at any more.

  Unpublishing or replacing a quiz leaves its photos on disk, and a publish that never
  completes leaves behind whatever was uploaded first. An image is collected when no
  question references its key *and* it is older than `:grace_seconds` (default 24h) —
  the grace is what keeps a photo that was uploaded a moment ago, for a quiz still being
  written, from being swept out from under it. Files in the uploads directory with no row
  at all (a crash between writing the file and inserting the row) go the same way.

  Options: `:grace_seconds`, `:now` (a `DateTime`, for tests).
  """
  @spec sweep_images(keyword()) :: %{
          images: non_neg_integer(),
          files: non_neg_integer(),
          bytes: non_neg_integer()
        }
  def sweep_images(opts \\ []) do
    grace = Keyword.get(opts, :grace_seconds, 86_400)
    cutoff = opts |> Keyword.get(:now, DateTime.utc_now()) |> DateTime.add(-grace, :second)

    orphans = orphan_images(cutoff)
    for {key, _size} <- orphans, do: delete_upload(key)
    delete_image_rows(Enum.map(orphans, &elem(&1, 0)))

    strays = stray_files(cutoff)
    for key <- strays, do: delete_upload(key)

    %{
      images: length(orphans),
      files: length(strays),
      bytes: orphans |> Enum.map(&elem(&1, 1)) |> Enum.sum()
    }
  end

  defp orphan_images(cutoff) do
    Repo.all(
      from i in Image,
        as: :image,
        where: i.inserted_at < ^cutoff,
        where:
          not exists(from q in Question, where: q.image_key == parent_as(:image).key, select: 1),
        select: {i.key, i.byte_size}
    )
  end

  # Chunked: every key becomes a bind parameter, and SQLite caps how many there may be.
  defp delete_image_rows(keys) do
    keys
    |> Enum.chunk_every(200)
    |> Enum.each(&Repo.delete_all(from(i in Image, where: i.key in ^&1)))
  end

  # Files the database has never heard of. Young ones may be an upload in flight.
  defp stray_files(cutoff) do
    case File.ls(Uploads.dir()) do
      {:ok, names} ->
        known = MapSet.new(Repo.all(from i in Image, select: i.key))

        Enum.filter(names, fn name ->
          not MapSet.member?(known, name) and written_before?(name, cutoff)
        end)

      {:error, _reason} ->
        []
    end
  end

  defp written_before?(name, cutoff) do
    case File.stat(Path.join(Uploads.dir(), name), time: :posix) do
      {:ok, %File.Stat{type: :regular, mtime: mtime}} ->
        DateTime.compare(DateTime.from_unix!(mtime), cutoff) == :lt

      _ ->
        false
    end
  end

  defp delete_upload(key), do: File.rm(Path.join(Uploads.dir(), key))

  ## Private (inline) quizzes

  @doc """
  Validates a private quiz document sent with room creation (QUIZ_FORMAT.md §5.7) and
  builds its pack without touching the database. Photos come inline as base64
  `image.data`; they are kept in memory by `Fazoura.Rooms.Images` under the returned keys,
  which the caller attaches to the room (or deletes if the room can't start).

  `spent` is the photo bytes the room already holds, and the returned total is what it
  holds afterwards: a selection resolves one quiz at a time (PROTOCOL.md §6.4), and
  `max_inline_bytes/0` bounds the room, not each quiz in it.
  """
  @spec inline_pack(term(), non_neg_integer()) ::
          {:ok, Pack.t(), [String.t()], non_neg_integer()}
          | {:error, Ecto.Changeset.t() | :image_too_large | :unsupported_image}
  def inline_pack(params, spent \\ 0) do
    with {:ok, params, images, spent} <- extract_inline_images(params, spent),
         {:ok, quiz} <-
           %Quiz{source: "inline", visibility: "private", questions: [], quiz_tags: []}
           |> Quiz.changeset(params)
           |> Ecto.Changeset.apply_action(:insert) do
      Images.put(images)
      {:ok, to_pack(quiz, &Images.url/1), Enum.map(images, &elem(&1, 0)), spent}
    end
  end

  defp extract_inline_images(%{"questions" => questions} = params, spent)
       when is_list(questions) do
    result = Enum.reduce_while(questions, {:ok, [], [], spent}, &take_inline_image/2)

    with {:ok, questions, images, bytes} <- result do
      {:ok, Map.put(params, "questions", Enum.reverse(questions)), Enum.reverse(images), bytes}
    end
  end

  defp extract_inline_images(params, spent), do: {:ok, params, [], spent}

  defp take_inline_image(question, {:ok, acc, images, bytes}) do
    case inline_image(question) do
      {:ok, question, nil} -> {:cont, {:ok, [question | acc], images, bytes}}
      {:ok, question, image} -> keep_image(question, image, acc, images, bytes)
      error -> {:halt, error}
    end
  end

  # Every photo is already under the per-image cap, but a room holds all of them in
  # memory for its whole life, so the total is what has to be bounded as well. The
  # running total is carried *across* the quizzes a selection names (PROTOCOL.md
  # §6.4): ten quizzes each just under the cap would otherwise be ten times the
  # memory one room is allowed.
  defp keep_image(question, {_key, _type, binary} = image, acc, images, bytes) do
    bytes = bytes + byte_size(binary)

    if bytes > max_inline_bytes(),
      do: {:halt, {:error, :quiz_too_large}},
      else: {:cont, {:ok, [question | acc], [image | images], bytes}}
  end

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

  # Same check as a stored upload: magic bytes *and* a well-formed header, so a private
  # quiz cannot smuggle in what a published one cannot.
  defp detect_image(binary), do: Uploads.validate(binary)

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
      version: quiz.version,
      id: quiz.id,
      slug: quiz.slug,
      title: quiz.title,
      description: quiz.description,
      language: quiz.language,
      tags: Enum.map(quiz.quiz_tags, & &1.tag),
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

  @doc "Builds a portable `.fazoura` package containing the full quiz and its photos."
  @spec archive(Quiz.t()) :: {:ok, binary()} | {:error, term()}
  def archive(%Quiz{} = quiz) do
    with {:ok, photos} <- archive_photos(quiz) do
      quiz |> to_document(owner?: true) |> archive_document() |> Archive.build(photos)
    end
  end

  @doc """
  Reads a `.fazoura` package into the quiz document params `create/2` and
  `Fazoura.Admin.create_preset/1` take, storing the photos it carries as ordinary
  uploads along the way.

  The photos are stored before the document is validated, so a package whose quiz turns
  out to be invalid leaves uploads behind with nothing pointing at them — which is
  precisely what `Fazoura.Quizzes.ImageSweeper` collects.
  """
  @spec read_archive(binary()) :: {:ok, map()} | {:error, Archive.reason() | photo_error()}
  def read_archive(binary) do
    with {:ok, %{document: document, photos: photos}} <- Archive.read(binary) do
      store_photos(document, &read_carried(photos, &1))
    end
  end

  defp read_carried(photos, path) do
    case Map.fetch(photos, path) do
      {:ok, bytes} -> {:ok, bytes}
      :error -> {:error, :not_in_the_package}
    end
  end

  defp archive_document(document) do
    questions =
      Enum.map(document.questions || [], fn question ->
        case question.image do
          %{key: key} = image when is_binary(key) ->
            question
            |> Map.delete(:image)
            |> Map.put(:image, %{path: Archive.media_path(key), alt: image.alt})

          _ ->
            question
        end
      end)

    Map.put(document, :questions, questions)
  end

  defp archive_photos(%Quiz{questions: questions}) do
    questions
    |> Enum.filter(& &1.image_key)
    |> Enum.reduce_while({:ok, %{}}, fn question, {:ok, photos} ->
      case Uploads.read(question.image_key) do
        {:ok, binary} ->
          {:cont, {:ok, Map.put(photos, Archive.media_path(question.image_key), binary)}}

        # A photo the quiz still references but the volume no longer has. The caller
        # answers with an error rather than a package missing a question's image,
        # because the point of the package is that it is self-contained.
        :error ->
          {:halt, {:error, :image_not_found}}
      end
    end)
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
      titles: [quiz.title],
      default_time_limit_ms: quiz.default_time_limit_ms,
      default_difficulty_multiplier: quiz.default_difficulty_multiplier,
      questions:
        Enum.map(quiz.questions, fn question ->
          %Pack.Question{
            id: question.id || "q#{question.position}",
            # Where this question came from, so a player can report what they
            # are looking at (QUIZ_FORMAT.md §5.9). It never leaves the server.
            quiz_id: quiz.id,
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

      params =
        case path |> File.read!() |> Jason.decode!() |> store_photos(&read_beside(dir, &1)) do
          {:ok, params} ->
            params

          # Raises rather than skipping. This runs on every deploy, and a preset whose
          # photo went missing should stop the release, not reach a party with a hole
          # in it.
          {:error, {reason, photo}} ->
            raise ArgumentError, "preset photo #{photo} was refused: #{inspect(reason)}"
        end

      {:ok, quiz} = Repo.transaction(fn -> upsert_builtin!(slug, params) end)
      quiz
    end
  end

  # A preset's photo, read from the file named by `image.path` beside the quiz.
  # `Path.expand` resolves any `..` first, so the check is on where the path actually
  # lands rather than on how it is spelled.
  defp read_beside(dir, relative) do
    path = Path.expand(relative, dir)

    if String.starts_with?(path, Path.expand(dir) <> "/"),
      do: File.read(path),
      else: {:error, :outside_the_quizzes_directory}
  end

  ## Photos that travel with their quiz

  @typedoc "Which photo went wrong, and why."
  @type photo_error :: {atom(), String.t()}

  # Swaps every question's `image.path` for the key of a stored upload, reading the bytes
  # through `read`. Shared by the two places a quiz arrives with its photos beside it
  # rather than uploaded first: the presets in `priv/quizzes` (QUIZ_FORMAT.md §6) and a
  # `.fazoura` package (§5.3b).
  #
  # Neither is special once it is in. The photos are ordinary uploads — a file in the
  # uploads directory, a row in `images`, swept like any other — so nothing downstream
  # has to know where they came from.
  @spec store_photos(map(), (String.t() -> {:ok, binary()} | {:error, atom()})) ::
          {:ok, map()} | {:error, photo_error()}
  defp store_photos(%{"questions" => questions} = params, read) when is_list(questions) do
    questions
    |> Enum.reduce_while({:ok, []}, fn question, {:ok, done} ->
      case store_photo(question, read) do
        {:ok, question} -> {:cont, {:ok, [question | done]}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
    |> case do
      {:ok, done} -> {:ok, Map.put(params, "questions", Enum.reverse(done))}
      {:error, _reason} = error -> error
    end
  end

  defp store_photos(params, _read), do: {:ok, params}

  defp store_photo(%{"image" => %{"path" => path} = image} = question, read)
       when is_binary(path) do
    with {:ok, binary} <- read.(path),
         {:ok, stored} <- Uploads.store_stable(binary) do
      register_photo(stored)
      {:ok, Map.put(question, "image", image |> Map.delete("path") |> Map.put("key", stored.key))}
    else
      {:error, reason} -> {:error, {reason, path}}
    end
  end

  defp store_photo(question, _read), do: {:ok, question}

  # Owned by a key no device holds: nobody can edit or unpublish one of these quizzes
  # through the API, and nobody else's quiz can reference its photos
  # (`Fazoura.Admin.create_preset/1` takes the same view). The key derives from the
  # bytes, so the row may already be there from an earlier sync or an identical photo.
  defp register_photo(stored) do
    {:ok, hash} = OwnerKey.hash(@preset_owner_key)

    Repo.get_by(Image, key: stored.key) ||
      Repo.insert!(%Image{
        key: stored.key,
        content_type: stored.content_type,
        byte_size: stored.byte_size,
        owner_key_hash: hash
      })
  end

  @doc """
  Upserts every `<dir>/<slug>.fazoura` package as a public built-in quiz, photos and all
  (QUIZ_FORMAT.md §6).

  The drop folder beside `priv/quizzes`: a package is one file, so a quiz written
  somewhere else — by `tools/fazoura-cli/fazoura quiz pack`, or downloaded from another server — can be
  put on a server by copying it in, with no JSON to unpack and no photos to publish
  first. The filename is the slug, so re-running updates the quiz it already made rather
  than adding a second one.

  Idempotent, and a directory that isn't there is simply no packages. Run by
  `priv/repo/seeds.exs` and by `Fazoura.Release.setup/0` on every deploy.
  """
  @spec sync_packages!() :: [Quiz.t()]
  def sync_packages! do
    Enum.flat_map(packages_dirs(), &sync_packages!/1)
  end

  @doc "The same, for one directory."
  @spec sync_packages!(String.t()) :: [Quiz.t()]
  def sync_packages!(dir) when is_binary(dir) do
    for path <- dir |> Path.join("*.fazoura") |> Path.wildcard() |> Enum.sort() do
      slug = Path.basename(path, ".fazoura")

      params =
        case path |> File.read!() |> read_archive() do
          {:ok, params} ->
            params

          # Loudly, like a preset with a missing photo: this runs on every deploy, and a
          # package that cannot be read should stop the release rather than leave the
          # server quietly missing a quiz someone put there.
          {:error, reason} ->
            raise ArgumentError,
                  "quiz package #{Path.basename(path)} was refused: #{inspect(reason)}"
        end

      {:ok, quiz} = Repo.transaction(fn -> upsert_builtin!(slug, params) end)
      quiz
    end
  end

  @doc """
  The directories `.fazoura` packages are read from, in the order they are read.

  The one that ships in `priv/packages` first, then the drop directory (`PACKAGES_DIR`)
  if there is one — so a package copied onto a server can replace a shipped one of the
  same slug, which is the only way to correct one without a deploy.
  """
  @spec packages_dirs() :: [String.t()]
  def packages_dirs do
    [
      Application.get_env(:fazoura, :packages_dir) || shipped_packages_dir(),
      Application.get_env(:fazoura, :packages_drop_dir)
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  # Asked of the running system, exactly as `sync_builtin!/1` asks for `priv/quizzes`.
  # A path expanded in `config.exs` is the path the *build* saw — `/src/priv/packages`
  # inside the Docker builder — which does not exist in the release that ships.
  defp shipped_packages_dir, do: Path.join(:code.priv_dir(:fazoura), "packages")

  defp upsert_builtin!(slug, params) do
    quiz =
      case Repo.get_by(Quiz, slug: slug) do
        nil ->
          %Quiz{slug: slug, source: "builtin", visibility: "public", questions: [], quiz_tags: []}

        existing ->
          Repo.delete_all(from(q in Question, where: q.quiz_id == ^existing.id))
          Repo.delete_all(from(t in Tag, where: t.quiz_id == ^existing.id))
          %{existing | questions: [], quiz_tags: []}
      end

    quiz |> Quiz.changeset(params) |> Repo.insert_or_update!()
  end

  # A revision counter: the quiz somebody saved is behind when its number is
  # lower than the one the server holds (QUIZ_FORMAT.md §2.1).
  defp increment_version(version) when is_integer(version), do: version + 1
  defp increment_version(_version), do: 1
end

defmodule Fazoura.Quizzes.Quiz do
  @moduledoc "A quiz with its tags and ordered questions (protocol/QUIZ_FORMAT.md §2.1)."

  use Ecto.Schema
  import Ecto.Changeset

  alias Fazoura.Quizzes.{Question, Tag}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # The document format this server reads and writes (QUIZ_FORMAT.md §2.1).
  # `<major>.<minor>`: a document whose major matches is readable, whatever its
  # minor, because a minor only ever adds keys an older reader ignores.
  @format_version "1.0"
  # Stored quizzes are public; inline (private) quizzes are never stored.
  @visibilities ~w(public private)
  @max_tags 10
  @max_questions 1024

  schema "quizzes" do
    field :slug, :string
    field :format_version, :string, default: @format_version
    # A revision counter, not a contract: +1 every time a published quiz is
    # replaced, so a device can tell its saved copy is behind.
    field :version, :integer, default: 1
    field :title, :string
    field :description, :string
    field :language, :string, default: "en"
    field :source, :string
    field :visibility, :string
    field :owner_key_hash, :string
    field :default_time_limit_ms, :integer, default: 30_000
    field :default_difficulty_multiplier, :boolean, default: false
    field :question_count, :integer, default: 0
    field :has_photos, :boolean, default: false

    has_many :quiz_tags, Tag, preload_order: [asc: :position], on_replace: :delete
    has_many :questions, Question, preload_order: [asc: :position], on_replace: :delete

    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{}

  def format_version, do: @format_version
  def visibilities, do: @visibilities
  def max_tags, do: @max_tags
  def max_questions, do: @max_questions

  @doc """
  `params` use the JSON document shape. Replaces all tags and questions, so the quiz must
  have `quiz_tags: []` and `questions: []` loaded (see `Fazoura.Quizzes`).
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(quiz, params) do
    params = normalize(params)

    quiz
    |> cast(params, [
      :format_version,
      :version,
      :title,
      :description,
      :language,
      :default_time_limit_ms,
      :default_difficulty_multiplier
    ])
    |> update_change(:title, &trim/1)
    |> validate_required([:format_version, :title])
    |> validate_change(:format_version, &readable_format/2)
    # Whatever the document claimed, what is stored is the format it was read
    # as: the row is built from the keys this server understands.
    |> put_change(:format_version, @format_version)
    |> validate_number(:version, greater_than: 0)
    |> validate_length(:title, min: 1, max: 80)
    |> validate_length(:description, max: 280)
    |> validate_length(:language, min: 2, max: 10)
    |> validate_number(:default_time_limit_ms,
      greater_than_or_equal_to: 10_000,
      less_than_or_equal_to: 120_000
    )
    |> put_tags(params["tags"])
    |> put_questions(params["questions"])
  end

  # An emptied field casts to the schema default — nil — rather than to "", so trimming
  # has to cope with one. `validate_required/2` is what reports it.
  defp trim(value) when is_binary(value), do: String.trim(value)
  defp trim(value), do: value

  # Tags are free text (§2.3): normalised, de-duplicated, order preserved.
  defp put_tags(changeset, tags) when is_list(tags) do
    cleaned = tags |> Enum.map(&Tag.normalize/1) |> Enum.reject(&(&1 == "")) |> Enum.uniq()

    changeset
    |> put_assoc(
      :quiz_tags,
      cleaned
      |> Enum.with_index(1)
      |> Enum.map(fn {tag, position} -> Tag.changeset(tag, position) end)
    )
    |> validate_tags(cleaned)
  end

  defp put_tags(changeset, _tags), do: add_error(changeset, :tags, tag_count_message())

  # Checked on the input list, like questions: put_assoc records no change when the tags
  # are the ones already stored, and validate_length would then skip them.
  defp validate_tags(changeset, cleaned) do
    cond do
      length(cleaned) not in 1..@max_tags ->
        add_error(changeset, :tags, tag_count_message())

      Enum.any?(cleaned, &(String.length(&1) > Tag.max_length())) ->
        add_error(changeset, :tags, "each tag must be at most #{Tag.max_length()} characters")

      true ->
        changeset
    end
  end

  defp tag_count_message, do: "must be a list of 1 to #{@max_tags} tags"

  defp put_questions(changeset, questions) when is_list(questions) do
    question_changesets =
      questions
      |> Enum.with_index(1)
      |> Enum.map(fn {params, position} -> Question.changeset(%Question{}, params, position) end)

    # Checked on the input list: validate_length skips unchanged assocs, and replacing
    # an already-empty question list with [] isn't a change.
    changeset
    |> put_assoc(:questions, question_changesets)
    |> then(fn changeset ->
      if length(questions) in 1..@max_questions,
        do: changeset,
        else:
          add_error(
            changeset,
            :questions,
            "must be a list of 1 to #{@max_questions} questions"
          )
    end)
    |> put_change(:question_count, length(questions))
    |> put_change(
      :has_photos,
      Enum.any?(question_changesets, &(Ecto.Changeset.get_field(&1, :type) == "text_photo"))
    )
  end

  defp put_questions(changeset, _questions),
    do: add_error(changeset, :questions, "must be a list of 1 to #{@max_questions} questions")

  # The document nests suggested room settings under `default_settings`.
  # A document written for the same major is readable: a minor only ever adds
  # keys, and an unknown key is ignored (PROTOCOL.md §1.1 says the same of the
  # wire). A different major is not.
  defp readable_format(:format_version, version) do
    if major(version) == major(@format_version),
      do: [],
      else: [format_version: "is format #{version}; this server reads #{@format_version}"]
  end

  defp major(version) do
    version |> to_string() |> String.split(".", parts: 2) |> hd()
  end

  defp normalize(%{} = params) do
    settings = if is_map(params["default_settings"]), do: params["default_settings"], else: %{}

    params
    |> put_present("default_time_limit_ms", settings["time_limit_ms"])
    |> put_present("default_difficulty_multiplier", settings["difficulty_multiplier"])
    |> update_present("format_version", &legacy_format_version/1)
    |> update_present("version", &legacy_version/1)
  end

  defp normalize(_params), do: %{}

  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)

  defp update_present(map, key, fun) do
    case Map.fetch(map, key) do
      {:ok, value} -> Map.put(map, key, fun.(value))
      :error -> map
    end
  end

  # `format_version: 1` is every document written before the format carried a
  # minor — presets in `priv/quizzes`, packages in `priv/packages`, and whatever
  # a device saved before it took an update. They are format 1.0.
  defp legacy_format_version(version) when is_integer(version), do: "#{version}.0"
  defp legacy_format_version(version), do: version

  # And `version: "1.4"` is the old revision scheme, where the minor did the
  # counting and the major never moved. "1.0" was the first revision, so the
  # counter that replaces it starts at 1.
  # An explicit `null` is a document saying nothing about its revision, which is
  # the same as not saying it: the first one. Passing the nil through reached
  # the database and came back as a NOT NULL violation.
  defp legacy_version(nil), do: 1

  defp legacy_version(version) when is_binary(version) do
    with [_major, minor] <- String.split(version, ".", parts: 2),
         {count, _rest} <- Integer.parse(minor) do
      count + 1
    else
      _ -> 1
    end
  end

  defp legacy_version(version), do: version
end

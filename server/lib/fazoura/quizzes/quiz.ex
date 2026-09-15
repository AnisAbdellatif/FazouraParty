defmodule Fazoura.Quizzes.Quiz do
  @moduledoc "A quiz with its tags and ordered questions (protocol/QUIZ_FORMAT.md §2.1)."

  use Ecto.Schema
  import Ecto.Changeset

  alias Fazoura.Quizzes.{Question, Tag}

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @format_version 1
  # Stored quizzes are public; inline (private) quizzes are never stored.
  @visibilities ~w(public private)
  @max_tags 10

  schema "quizzes" do
    field :slug, :string
    field :format_version, :integer, default: @format_version
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
      :title,
      :description,
      :language,
      :default_time_limit_ms,
      :default_difficulty_multiplier
    ])
    |> update_change(:title, &String.trim/1)
    |> validate_required([:format_version, :title])
    |> validate_number(:format_version, equal_to: @format_version)
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
      if length(questions) in 1..100,
        do: changeset,
        else: add_error(changeset, :questions, "must be a list of 1 to 100 questions")
    end)
    |> put_change(:question_count, length(questions))
    |> put_change(
      :has_photos,
      Enum.any?(question_changesets, &(Ecto.Changeset.get_field(&1, :type) == "text_photo"))
    )
  end

  defp put_questions(changeset, _questions),
    do: add_error(changeset, :questions, "must be a list of 1 to 100 questions")

  # The document nests suggested room settings under `default_settings`.
  defp normalize(%{} = params) do
    settings = if is_map(params["default_settings"]), do: params["default_settings"], else: %{}

    params
    |> put_present("default_time_limit_ms", settings["time_limit_ms"])
    |> put_present("default_difficulty_multiplier", settings["difficulty_multiplier"])
  end

  defp normalize(_params), do: %{}

  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)
end

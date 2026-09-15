defmodule Fazoura.Quizzes.Question do
  @moduledoc "One quiz question (protocol/QUIZ_FORMAT.md §2.2)."

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @types ~w(text text_photo)
  @difficulties ~w(easy medium hard)

  schema "quiz_questions" do
    field :position, :integer
    field :type, :string
    field :prompt, :string
    field :accepted_answers, {:array, :string}, default: []
    field :difficulty, :string, default: "easy"
    field :time_limit_ms, :integer
    field :image_key, :string
    field :image_alt, :string
    field :explanation, :string

    belongs_to :quiz, Fazoura.Quizzes.Quiz

    timestamps(type: :utc_datetime)
  end

  @type t :: %__MODULE__{}

  def types, do: @types
  def difficulties, do: @difficulties

  @doc "`params` use the JSON document shape; `position` is 1-based play order."
  @spec changeset(t(), map(), pos_integer()) :: Ecto.Changeset.t()
  def changeset(question, params, position) do
    question
    |> cast(normalize(params), [
      :type,
      :prompt,
      :accepted_answers,
      :difficulty,
      :time_limit_ms,
      :image_key,
      :image_alt,
      :explanation
    ])
    |> put_change(:position, position)
    |> update_change(:prompt, &String.trim/1)
    |> update_change(:accepted_answers, &clean_answers/1)
    |> validate_required([:type, :prompt, :accepted_answers])
    |> validate_inclusion(:type, @types)
    |> validate_inclusion(:difficulty, @difficulties)
    |> validate_length(:prompt, min: 1, max: 280)
    |> validate_length(:accepted_answers, max: 10)
    |> require_answers()
    |> validate_change(:accepted_answers, fn :accepted_answers, answers ->
      if Enum.all?(answers, &(String.length(&1) <= 100)),
        do: [],
        else: [accepted_answers: "each answer must be at most 100 characters"]
    end)
    |> validate_number(:time_limit_ms,
      greater_than_or_equal_to: 10_000,
      less_than_or_equal_to: 120_000
    )
    |> validate_length(:image_alt, max: 140)
    |> validate_length(:explanation, max: 280)
    |> validate_image()
  end

  # The document nests the photo as `image: {key, alt}`; the table flattens it.
  defp normalize(%{} = params) do
    image = Map.get(params, "image")

    params
    |> Map.put("image_key", if(is_map(image), do: image["key"]))
    |> Map.put("image_alt", if(is_map(image), do: image["alt"]))
  end

  defp normalize(_params), do: %{}

  # Checked on the field, not the change: an empty list equals the schema default,
  # so Ecto records no change and validate_length would skip it.
  defp require_answers(changeset) do
    case get_field(changeset, :accepted_answers) do
      [_ | _] -> changeset
      _ -> add_error(changeset, :accepted_answers, "needs at least one accepted answer")
    end
  end

  defp clean_answers(answers) do
    answers |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == "")) |> Enum.uniq()
  end

  defp validate_image(changeset) do
    case {get_field(changeset, :type), get_field(changeset, :image_key)} do
      {"text_photo", nil} ->
        add_error(changeset, :image, "a photo question needs an image")

      {"text", key} when is_binary(key) ->
        add_error(changeset, :image, "text questions have no image")

      _ ->
        changeset
    end
  end
end

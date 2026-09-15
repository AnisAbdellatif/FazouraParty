defmodule Fazoura.Settings do
  @moduledoc """
  Settings an admin can change at runtime (protocol/ADMIN.md).

  Values are JSON text in one small table, so a new setting needs no migration. Reads fall
  back to the code default, which is what a fresh database uses.
  """

  alias Fazoura.Quizzes.Tag
  alias Fazoura.Repo
  alias Fazoura.Settings.Setting

  @suggested_tags "suggested_tags"
  @max_suggested_tags 30

  @doc "Tags the apps offer as quick picks (QUIZ_FORMAT.md §2.3)."
  @spec suggested_tags() :: [String.t()]
  def suggested_tags do
    case decode(get(@suggested_tags)) do
      [_ | _] = tags -> tags
      _ -> Tag.default_suggested()
    end
  end

  @doc """
  Replaces the suggested tags. They are normalised and de-duplicated like any other tag;
  an empty list restores the built-in defaults.
  """
  @spec put_suggested_tags([String.t()]) ::
          {:ok, [String.t()]} | {:error, :too_many_tags | :tag_too_long}
  def put_suggested_tags(tags) when is_list(tags) do
    cleaned = tags |> Enum.map(&Tag.normalize/1) |> Enum.reject(&(&1 == "")) |> Enum.uniq()

    cond do
      length(cleaned) > @max_suggested_tags ->
        {:error, :too_many_tags}

      Enum.any?(cleaned, &(String.length(&1) > Tag.max_length())) ->
        {:error, :tag_too_long}

      cleaned == [] ->
        put(@suggested_tags, Tag.default_suggested())
        {:ok, Tag.default_suggested()}

      true ->
        put(@suggested_tags, cleaned)
        {:ok, cleaned}
    end
  end

  @spec max_suggested_tags() :: pos_integer()
  def max_suggested_tags, do: @max_suggested_tags

  @spec get(String.t()) :: String.t() | nil
  def get(key) do
    case Repo.get(Setting, key) do
      nil -> nil
      setting -> setting.value
    end
  end

  @spec put(String.t(), term()) :: :ok
  def put(key, value) do
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    Repo.insert!(
      %Setting{key: key, value: Jason.encode!(value), inserted_at: now, updated_at: now},
      on_conflict: [set: [value: Jason.encode!(value), updated_at: now]],
      conflict_target: :key
    )

    :ok
  end

  defp decode(nil), do: nil

  defp decode(json) do
    case Jason.decode(json) do
      {:ok, value} -> value
      {:error, _reason} -> nil
    end
  end
end

defmodule Fazoura.Quizzes.OwnerKey do
  @moduledoc """
  Per-device secret that owns custom quizzes until accounts exist
  (protocol/QUIZ_FORMAT.md §4). Only its SHA-256 hash is stored.
  """

  @format ~r/\A[A-Za-z0-9_-]{32,128}\z/

  @spec hash(term()) :: {:ok, String.t()} | :error
  def hash(key) when is_binary(key) do
    if key =~ @format,
      do: {:ok, :crypto.hash(:sha256, key) |> Base.encode16(case: :lower)},
      else: :error
  end

  def hash(_key), do: :error
end

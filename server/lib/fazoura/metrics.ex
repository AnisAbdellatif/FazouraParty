defmodule Fazoura.Metrics do
  @moduledoc """
  Cheap lock-free counters for the admin dashboard, reset when the node restarts.

  Anything that must survive a restart belongs in the database instead.
  """

  @counters [:rooms_created]

  @doc "Creates the counters. Called once by `Fazoura.Application`."
  @spec setup() :: :ok
  def setup do
    :persistent_term.put(__MODULE__, :counters.new(length(@counters), [:write_concurrency]))
  end

  @spec increment(atom()) :: :ok
  def increment(name) do
    case ref() do
      nil -> :ok
      ref -> :counters.add(ref, index(name), 1)
    end
  end

  @spec get(atom()) :: non_neg_integer()
  def get(name) do
    case ref() do
      nil -> 0
      ref -> :counters.get(ref, index(name))
    end
  end

  @spec snapshot() :: %{atom() => non_neg_integer()}
  def snapshot, do: Map.new(@counters, &{&1, get(&1)})

  defp ref, do: :persistent_term.get(__MODULE__, nil)

  defp index(name) do
    case Enum.find_index(@counters, &(&1 == name)) do
      nil -> raise ArgumentError, "unknown counter #{inspect(name)}"
      index -> index + 1
    end
  end
end

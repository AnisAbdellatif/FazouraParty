defmodule Fazoura.Rooms.Images do
  @moduledoc """
  Photos of private quizzes, held in memory only while their room is alive
  (protocol/QUIZ_FORMAT.md §5.7). Served at `/api/room-images/<key>`; keys are random
  and unguessable.

  The ETS table is public so request processes read and write directly; this process
  owns it and deletes a room's photos when the room process exits.
  """

  use GenServer

  alias Fazoura.Uploads

  @table __MODULE__

  @type image :: {key :: String.t(), content_type :: String.t(), binary()}

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @spec new_key(String.t()) :: String.t()
  def new_key(ext),
    do: Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false) <> "." <> ext

  @spec url(String.t()) :: String.t()
  def url(key), do: Uploads.public_url() <> "/api/room-images/" <> key

  # Every room's inline photos together. One room is held to `Quizzes.max_inline_bytes/0`,
  # but rooms are many and anonymous: this is what bounds the memory all of them can
  # take between them, so a flood of rooms full of photos meets a "busy" rather than
  # the node running out of memory.
  @default_max_total_bytes 1024 * 1024 * 1024
  @total :__total_bytes__

  @doc "The most photo bytes all rooms together may hold."
  @spec max_total_bytes() :: pos_integer()
  def max_total_bytes,
    do: Application.get_env(:fazoura, :max_room_image_bytes, @default_max_total_bytes)

  @doc "Photo bytes held right now, across every room."
  @spec total_bytes() :: non_neg_integer()
  def total_bytes do
    case :ets.lookup(@table, @total) do
      [{@total, bytes}] -> bytes
      [] -> 0
    end
  end

  @doc "How many photos are held, across every room."
  @spec count() :: non_neg_integer()
  def count, do: :ets.select_count(@table, [{{:"$1", :_, :_}, [{:is_binary, :"$1"}], [true]}])

  @spec put([image()]) :: :ok | {:error, :too_many_rooms}
  def put([]), do: :ok

  def put(images) do
    bytes = images |> Enum.map(fn {_key, _type, binary} -> byte_size(binary) end) |> Enum.sum()

    if :ets.update_counter(@table, @total, {2, bytes}, {@total, 0}) > max_total_bytes() do
      :ets.update_counter(@table, @total, {2, -bytes})
      {:error, :too_many_rooms}
    else
      :ets.insert(@table, images)
      :ok
    end
  end

  @spec fetch(String.t()) :: {:ok, String.t(), binary()} | :error
  def fetch(key) when is_binary(key) do
    case :ets.lookup(@table, key) do
      [{^key, content_type, binary}] -> {:ok, content_type, binary}
      [] -> :error
    end
  end

  @spec delete([String.t()]) :: :ok
  def delete(keys) do
    Enum.each(keys, fn key ->
      case :ets.take(@table, key) do
        [{^key, _type, binary}] -> :ets.update_counter(@table, @total, {2, -byte_size(binary)})
        [] -> :ok
      end
    end)
  end

  @doc "Deletes `keys` once `pid` (the room) exits."
  @spec attach([String.t()], pid()) :: :ok
  def attach([], _pid), do: :ok
  def attach(keys, pid), do: GenServer.call(__MODULE__, {:attach, keys, pid})

  @doc """
  Makes `keys` the room's photos, deleting whichever it held before.

  For a host choosing quizzes again: the photos of a selection that has been replaced
  are no longer anybody's, and keeping them until the room ended let a host grow the
  server's memory 8 MB at a time by re-sending the same selection.
  """
  @spec replace([String.t()], pid()) :: :ok
  def replace(keys, pid), do: GenServer.call(__MODULE__, {:replace, keys, pid})

  ## Callbacks

  # State: each room's pid to its monitor and the photo keys it holds.
  @impl true
  def init(nil) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, %{}}
  end

  @impl true
  def handle_call({:attach, keys, pid}, _from, rooms) do
    {:reply, :ok, Map.put(rooms, pid, {monitor(rooms, pid), held(rooms, pid) ++ keys})}
  end

  def handle_call({:replace, keys, pid}, _from, rooms) do
    delete(held(rooms, pid) -- keys)
    {:reply, :ok, Map.put(rooms, pid, {monitor(rooms, pid), keys})}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, _reason}, rooms) do
    {{_ref, keys}, rooms} = Map.pop(rooms, pid, {nil, []})
    delete(keys)
    {:noreply, rooms}
  end

  defp held(rooms, pid), do: rooms |> Map.get(pid, {nil, []}) |> elem(1)

  defp monitor(rooms, pid) do
    case Map.fetch(rooms, pid) do
      {:ok, {ref, _keys}} -> ref
      :error -> Process.monitor(pid)
    end
  end
end

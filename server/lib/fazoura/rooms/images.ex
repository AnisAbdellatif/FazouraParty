defmodule Fazoura.Rooms.Images do
  @moduledoc """
  Photos of private quizzes, held in memory only while their room is alive
  (protocol/QUIZ_FORMAT.md §5.7). Served at `/api/room-images/<key>`; keys are random
  and unguessable.

  The ETS table is public so request processes read and write directly; this process
  owns it and deletes a room's photos when the room process exits.
  """

  use GenServer

  @table __MODULE__

  @type image :: {key :: String.t(), content_type :: String.t(), binary()}

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @spec new_key(String.t()) :: String.t()
  def new_key(ext),
    do: Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false) <> "." <> ext

  @spec url(String.t()) :: String.t()
  def url(key), do: FazouraWeb.Endpoint.url() <> "/api/room-images/" <> key

  @spec put([image()]) :: :ok
  def put(images) do
    :ets.insert(@table, images)
    :ok
  end

  @spec fetch(String.t()) :: {:ok, String.t(), binary()} | :error
  def fetch(key) do
    case :ets.lookup(@table, key) do
      [{^key, content_type, binary}] -> {:ok, content_type, binary}
      [] -> :error
    end
  end

  @spec delete([String.t()]) :: :ok
  def delete(keys) do
    Enum.each(keys, &:ets.delete(@table, &1))
  end

  @doc "Deletes `keys` once `pid` (the room) exits."
  @spec attach([String.t()], pid()) :: :ok
  def attach([], _pid), do: :ok
  def attach(keys, pid), do: GenServer.call(__MODULE__, {:attach, keys, pid})

  ## Callbacks

  @impl true
  def init(nil) do
    :ets.new(@table, [:named_table, :public, :set, read_concurrency: true])
    {:ok, %{}}
  end

  @impl true
  def handle_call({:attach, keys, pid}, _from, rooms) do
    ref = Process.monitor(pid)
    {:reply, :ok, Map.put(rooms, ref, keys)}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, rooms) do
    {keys, rooms} = Map.pop(rooms, ref, [])
    delete(keys)
    {:noreply, rooms}
  end
end

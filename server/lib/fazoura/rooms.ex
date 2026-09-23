defmodule Fazoura.Rooms do
  @moduledoc """
  Public API for live rooms. Each room is a `Fazoura.Rooms.RoomServer` registered in
  `Fazoura.Rooms.Registry` under its room code.
  """

  alias Fazoura.Game.Pack
  alias Fazoura.Metrics
  alias Fazoura.Rooms.{Images, Listing, RoomServer, Tokens}

  @code_alphabet ~c"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
  @code_length 6

  # Rooms are free to create and live in memory for up to ten minutes without anyone
  # joining, so an unbounded count is a way to exhaust the node's memory. This is far
  # above any real party's needs and only bites a flood.
  @max_rooms 500

  @doc """
  Starts a room for `pack`. Options: `:now` (0-arity fun returning epoch ms, for tests),
  `:mode` (`:cloud` | `:lan`), `:image_keys` (private-quiz photos in
  `Fazoura.Rooms.Images`, freed when the room exits).
  """
  @spec create(Pack.t(), keyword()) ::
          {:ok, String.t(), String.t()} | {:error, :empty_pack | :too_many_rooms}
  def create(pack, opts \\ [])

  # A pack with no questions is only legal as the empty lobby a room is created
  # in; a selection that came to nothing is a mistake (PROTOCOL.md §6.4).
  def create(%Pack{questions: [], titles: [_ | _]}, _opts), do: {:error, :empty_pack}

  def create(%Pack{} = pack, opts) do
    if count() >= max_rooms() do
      {:error, :too_many_rooms}
    else
      start_room(pack, opts)
    end
  end

  @doc "This module's part of `protocol/fixtures/constants.json` (see `Fazoura.Game.constants/0`)."
  @spec constants() :: %{String.t() => term()}
  def constants,
    do: %{"room_code_alphabet" => to_string(@code_alphabet), "room_code_length" => @code_length}

  @doc "How many rooms are live on this node."
  @spec count() :: non_neg_integer()
  def count, do: Registry.count(Fazoura.Rooms.Registry)

  @doc "The most rooms this node will run at once."
  @spec max_rooms() :: pos_integer()
  def max_rooms, do: Application.get_env(:fazoura, :max_rooms, @max_rooms)

  defp start_room(%Pack{} = pack, opts) do
    {image_keys, server_opts} = Keyword.pop(opts, :image_keys, [])
    code = generate_code()
    spec = {RoomServer, Keyword.merge(server_opts, code: code, pack: pack)}

    case DynamicSupervisor.start_child(Fazoura.Rooms.Supervisor, spec) do
      {:ok, pid} ->
        :ok = Images.attach(image_keys, pid)
        Metrics.increment(:rooms_created)
        {:ok, code, Tokens.host_token(code)}

      # A code collision, not a capacity problem: retry without re-checking the cap.
      {:error, {:already_started, _pid}} ->
        start_room(pack, opts)
    end
  end

  @doc "Registers `pid` (a channel) in the room. Returns the join reply and the room pid."
  @spec join(String.t(), pid(), map()) :: {:ok, map(), pid()} | {:error, atom()}
  def join(code, pid, params, meta \\ %{}), do: call(code, {:join, pid, params, meta})

  @spec intent(String.t(), pid(), Fazoura.Game.intent()) :: :ok | {:error, atom()}
  def intent(code, pid, intent), do: call(code, {:intent, pid, intent})

  @doc """
  A snapshot of every running room, for the admin dashboard. Rooms that stop while being
  asked are simply left out.
  """
  @spec active() :: [map()]
  def active do
    Fazoura.Rooms.Registry
    |> Registry.select([{{:_, :"$1", :_}, [], [:"$1"]}])
    |> Enum.flat_map(fn pid ->
      try do
        [GenServer.call(pid, :summary, 200)]
      catch
        :exit, _reason -> []
      end
    end)
    |> Enum.sort_by(& &1.code)
  end

  @doc "Every room its host chose to list (PROTOCOL.md §3.5); see `Fazoura.Rooms.Listing`."
  @spec listed() :: [map()]
  defdelegate listed, to: Listing, as: :all

  @doc """
  Tells every live room to close with `shutdown` (PROTOCOL.md §5.2). Called by
  `Fazoura.Rooms.Drain` while the sockets are still open, so a deploy ends games out
  loud instead of leaving clients to discover it on a failed rejoin.
  """
  @spec shutdown_all() :: non_neg_integer()
  def shutdown_all do
    pids = Registry.select(Fazoura.Rooms.Registry, [{{:_, :"$1", :_}, [], [:"$1"]}])
    for pid <- pids, do: send(pid, :shutdown)
    length(pids)
  end

  @doc """
  Whether `host_token` still opens the live room `code`, and what it is doing.

  `{:error, :room_not_found}` covers both "no such room" and "not with that
  token", deliberately: the caller is a device asking whether the room it
  remembers is still worth offering, and either answer means forget it
  (PROTOCOL.md §3.3).
  """
  @spec status(String.t(), String.t() | nil) :: {:ok, map()} | {:error, :room_not_found}
  def status(code, host_token), do: call(code, {:status, host_token})

  @doc """
  The stored quiz a question in this room was snapshotted from, for somebody in
  the room who wants to report it (QUIZ_FORMAT.md §5.9).

  `token` is either token a join issues, and a wrong one gets `room_not_found`
  rather than a refusal — a caller who is not in the room is not told it exists.
  `question_id` may be nil, meaning the question the room is on.
  """
  @spec source_quiz(String.t(), String.t() | nil, String.t() | nil) ::
          {:ok, String.t()}
          | {:error, :room_not_found | :question_not_found | :quiz_not_public}
  def source_quiz(code, question_id, token),
    do: call(code, {:source_quiz, question_id, token})

  @doc """
  What a report about `player_id` keeps (PROTOCOL.md §3.5), for somebody in the room
  holding either token it issued.
  """
  @spec player_report(String.t(), String.t(), String.t() | nil) ::
          {:ok, Fazoura.Moderation.reported()} | {:error, atom()}
  def player_report(code, player_id, token),
    do: call(code, {:player_report, player_id, token})

  @doc "Ends a live room, as its host closing it would. For an admin answering a report."
  @spec close(String.t()) :: :ok | {:error, :room_not_found}
  def close(code) do
    case Registry.lookup(Fazoura.Rooms.Registry, code) do
      [{pid, _value}] ->
        send(pid, :admin_close)
        :ok

      [] ->
        {:error, :room_not_found}
    end
  end

  @doc "Forces timer/expiry evaluation now. Used by tests with an injected clock."
  @spec tick(String.t()) :: :ok | {:error, :room_not_found}
  def tick(code), do: call(code, :tick)

  defp call(code, message) when is_binary(code) do
    case Registry.lookup(Fazoura.Rooms.Registry, code) do
      [{pid, _value}] ->
        try do
          GenServer.call(pid, message)
        catch
          :exit, _reason -> {:error, :room_not_found}
        end

      [] ->
        {:error, :room_not_found}
    end
  end

  defp call(_code, _message), do: {:error, :room_not_found}

  defp generate_code do
    for _ <- 1..@code_length, into: "", do: <<Enum.random(@code_alphabet)>>
  end
end

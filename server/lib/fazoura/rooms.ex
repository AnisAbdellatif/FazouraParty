defmodule Fazoura.Rooms do
  @moduledoc """
  Public API for live rooms. Each room is a `Fazoura.Rooms.RoomServer` registered in
  `Fazoura.Rooms.Registry` under its room code.
  """

  alias Fazoura.Game.Pack
  alias Fazoura.Metrics
  alias Fazoura.Rooms.{Images, RoomServer}

  @code_alphabet ~c"ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
  @code_length 6

  @doc """
  Starts a room for `pack`. Options: `:now` (0-arity fun returning epoch ms, for tests),
  `:mode` (`:cloud` | `:lan`), `:image_keys` (private-quiz photos in
  `Fazoura.Rooms.Images`, freed when the room exits).
  """
  @spec create(Pack.t(), keyword()) :: {:ok, String.t(), String.t()} | {:error, :empty_pack}
  def create(pack, opts \\ [])
  def create(%Pack{questions: []}, _opts), do: {:error, :empty_pack}

  def create(%Pack{} = pack, opts) do
    {image_keys, server_opts} = Keyword.pop(opts, :image_keys, [])
    code = generate_code()
    spec = {RoomServer, Keyword.merge(server_opts, code: code, pack: pack)}

    case DynamicSupervisor.start_child(Fazoura.Rooms.Supervisor, spec) do
      {:ok, pid} ->
        :ok = Images.attach(image_keys, pid)
        Metrics.increment(:rooms_created)
        {:ok, code, RoomServer.host_token(code)}

      {:error, {:already_started, _pid}} ->
        create(pack, opts)
    end
  end

  @doc "Registers `pid` (a channel) in the room. Returns the join reply and the room pid."
  @spec join(String.t(), pid(), map()) :: {:ok, map(), pid()} | {:error, atom()}
  def join(code, pid, params), do: call(code, {:join, pid, params})

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

defmodule Fazoura.Rooms.Limits do
  @moduledoc """
  How much of the node one caller may hold at once: rooms created from one address, and
  rooms joined over one connection.

  A room lives for as long as somebody is connected to it, and one connection could join
  any number of them, so a single caller creating rooms and sitting in each could fill
  the node's `Fazoura.Rooms.max_rooms/0` and shut every real host out. The rate limit on
  creating rooms only slowed that down; this bounds it.

  Counted with a duplicate-key `Registry`: the room process registers under its creator's
  address, a channel process under its connection, and the registry forgets each the
  moment that process exits. So the counts cannot drift, and nothing has to clean up.
  """

  @registry __MODULE__

  # A host starts a handful of rooms an evening, and a school behind one address might
  # run several parties at once; nobody real holds more than this.
  @default_rooms_per_address 10

  # An IPv6 /64 is one subscriber (`FazouraWeb.ClientIp`), but one who owns a /48 has
  # 65,536 of those. The wider prefix gets a wider allowance of its own.
  @default_rooms_per_network 40

  # The app is in one room at a time. A little slack for a rejoin that lands before the
  # old channel has gone.
  @default_rooms_per_connection 3

  def child_spec(_opts), do: Registry.child_spec(keys: :duplicate, name: @registry)

  @doc """
  Whether a caller at `address` (as `ClientIp` gives it) may create another room.
  `nil` — no address known — is not limited here; the node-wide cap still is.
  """
  @spec may_create?(String.t() | nil) :: boolean()
  def may_create?(nil), do: true

  def may_create?(address) do
    Enum.all?(creator_keys(address), fn {key, limit} -> count(key) < limit end)
  end

  @doc "Registers the calling room process as created from `address`."
  @spec created_by(String.t() | nil) :: :ok
  def created_by(nil), do: :ok

  def created_by(address) do
    for {key, _limit} <- creator_keys(address), do: Registry.register(@registry, key, nil)
    :ok
  end

  @doc "Whether the connection `transport` may join one more room."
  @spec may_join?(pid()) :: boolean()
  def may_join?(transport), do: count({:connection, transport}) < rooms_per_connection()

  @doc "Registers the calling channel process as one of `transport`'s rooms."
  @spec joined_over(pid()) :: :ok
  def joined_over(transport) do
    {:ok, _owner} = Registry.register(@registry, {:connection, transport}, nil)
    :ok
  end

  defp count(key), do: @registry |> Registry.lookup(key) |> length()

  defp creator_keys(address) do
    address_key = {{:creator, address}, config(:rooms_per_address, @default_rooms_per_address)}

    case ipv6_network(address) do
      nil ->
        [address_key]

      network ->
        [
          address_key,
          {{:network, network}, config(:rooms_per_network, @default_rooms_per_network)}
        ]
    end
  end

  # "2001:db8:1:2::/64" → "2001:db8:1::/48"
  defp ipv6_network(address) do
    with true <- String.ends_with?(address, "/64"),
         {:ok, {a, b, c, _, _, _, _, _}} <-
           address |> String.trim_trailing("/64") |> String.to_charlist() |> :inet.parse_address() do
      (:inet.ntoa({a, b, c, 0, 0, 0, 0, 0}) |> to_string()) <> "/48"
    else
      _ -> nil
    end
  end

  defp rooms_per_connection,
    do: config(:rooms_per_connection, @default_rooms_per_connection)

  defp config(key, default),
    do: :fazoura |> Application.get_env(__MODULE__, []) |> Keyword.get(key, default)
end

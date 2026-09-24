defmodule Fazoura.Moderation.IpHash do
  @moduledoc """
  A connection's IP address as something that can be matched but not read.

  HMAC-SHA256 under a key derived from the server's `secret_key_base`: the same address
  always gives the same hash, so a ban can recognise it, but the address cannot be
  recovered from the hash, and without the secret it cannot even be confirmed by
  hashing a guess. So the database never holds an address in the clear (privacy
  policy, "Reporting a player").

  Rotating `secret_key_base` changes every hash, which lifts every ban. That is
  acceptable: bans last at most 90 days anyway.
  """

  alias Plug.Crypto.KeyGenerator

  @spec hash(String.t() | nil) :: String.t() | nil
  def hash(nil), do: nil

  def hash(ip) when is_binary(ip) do
    :hmac
    |> :crypto.mac(:sha256, key(), ip)
    |> Base.encode16(case: :lower)
  end

  # Derived once per boot: the derivation is deliberately slow.
  defp key do
    case :persistent_term.get({__MODULE__, :key}, nil) do
      nil ->
        secret = FazouraWeb.Endpoint.config(:secret_key_base)
        key = KeyGenerator.generate(secret, "fazoura ip hash", length: 32)
        :persistent_term.put({__MODULE__, :key}, key)
        key

      key ->
        key
    end
  end
end

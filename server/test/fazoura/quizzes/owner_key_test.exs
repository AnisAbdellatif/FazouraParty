defmodule Fazoura.Quizzes.OwnerKeyTest do
  @moduledoc """
  The publisher key's shape, which is a contract with the app (QUIZ_FORMAT.md §4).

  There are no accounts: this key is the only thing that lets a device replace or
  unpublish what it published. The app generates it (`generateOwnerKey`, tested on that
  side against the same rule) and the server decides what it will accept — so the two
  agreeing is what makes publishing work at all, and nothing tested it. A device whose
  key this module rejects cannot publish, edit or unpublish anything, and there is no
  error path for it to recover through: it simply never becomes an owner.
  """

  use ExUnit.Case, async: true

  alias Fazoura.Quizzes.OwnerKey

  # Exactly what the app produces: base64url of 32 random bytes with the padding
  # stripped, 43 characters. Written out rather than generated so a change on either
  # side has to come past this line.
  @app_key "PGP3ExnPCZ3JYcBJ0kE8cPHz9xMLs1qOaF9TKYQZL0A"

  test "the key the app generates is one the server takes" do
    assert String.length(@app_key) == 43
    assert {:ok, _hash} = OwnerKey.hash(@app_key)
  end

  test "only the hash is ever what a caller could hold" do
    {:ok, hash} = OwnerKey.hash(@app_key)

    assert hash =~ ~r/\A[0-9a-f]{64}\z/
    refute String.contains?(hash, @app_key)
    assert OwnerKey.hash(@app_key) == {:ok, hash}
  end

  test "URL-safe characters only, because it travels in a header" do
    assert {:ok, _} = OwnerKey.hash(String.duplicate("a", 32))
    assert {:ok, _} = OwnerKey.hash(String.duplicate("-", 32))
    assert {:ok, _} = OwnerKey.hash(String.duplicate("_", 32))

    # base64's non-URL-safe alphabet, which is the mistake an app-side change would make.
    assert OwnerKey.hash(String.duplicate("a", 31) <> "+") == :error
    assert OwnerKey.hash(String.duplicate("a", 31) <> "/") == :error
    assert OwnerKey.hash(String.duplicate("a", 31) <> "=") == :error
  end

  test "at least 32 characters, and no more than 128" do
    assert OwnerKey.hash(String.duplicate("a", 31)) == :error
    assert {:ok, _} = OwnerKey.hash(String.duplicate("a", 32))
    assert {:ok, _} = OwnerKey.hash(String.duplicate("a", 128))
    assert OwnerKey.hash(String.duplicate("a", 129)) == :error
  end

  test "anything that is not a string is not a key" do
    for value <- [nil, "", 42, %{}, ["a-key-long-enough-to-be-a-key-xx"]] do
      assert OwnerKey.hash(value) == :error
    end
  end
end

defmodule Fazoura.SettingsTest do
  # SQLite's sandbox does not support concurrent tests.
  use Fazoura.DataCase, async: false

  alias Fazoura.Quizzes.Tag
  alias Fazoura.Settings

  test "suggested tags fall back to the built-in list" do
    assert Settings.suggested_tags() == Tag.default_suggested()
  end

  test "saving normalises, de-duplicates and keeps the order" do
    assert {:ok, tags} = Settings.put_suggested_tags(["  Pub   QUIZ ", "pub quiz", "80s", "  "])
    assert tags == ["pub quiz", "80s"]
    assert Settings.suggested_tags() == ["pub quiz", "80s"]

    assert {:ok, ["movies"]} = Settings.put_suggested_tags(["Movies"])
    assert Settings.suggested_tags() == ["movies"]
  end

  test "limits the list and the tags in it" do
    assert Settings.put_suggested_tags(Enum.map(1..31, &"tag #{&1}")) == {:error, :too_many_tags}
    assert Settings.put_suggested_tags([String.duplicate("a", 25)]) == {:error, :tag_too_long}
    assert Settings.suggested_tags() == Tag.default_suggested()
  end

  test "an empty list restores the defaults" do
    {:ok, _tags} = Settings.put_suggested_tags(["only this"])
    assert {:ok, defaults} = Settings.put_suggested_tags([])
    assert defaults == Tag.default_suggested()
    assert Settings.suggested_tags() == Tag.default_suggested()
  end

  test "a value that isn't a list of tags falls back to the defaults" do
    Settings.put("suggested_tags", "not a list")
    assert Settings.suggested_tags() == Tag.default_suggested()
  end

  test "get/put round-trips any JSON value" do
    assert Settings.get("nope") == nil
    :ok = Settings.put("nope", %{"a" => 1})
    assert Settings.get("nope") == ~s({"a":1})
    :ok = Settings.put("nope", %{"a" => 2})
    assert Settings.get("nope") == ~s({"a":2})
  end
end

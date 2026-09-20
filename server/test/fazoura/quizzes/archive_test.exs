defmodule Fazoura.Quizzes.ArchiveTest do
  @moduledoc """
  The `.fazoura` container on its own (QUIZ_FORMAT.md §5.3b) — no database, no uploads.

  `read/1` is fed files from outside the server, so most of this is about what it does
  with ones that are not what they claim to be.
  """
  use ExUnit.Case, async: true

  import ExUnit.CaptureLog

  alias Fazoura.Quizzes.Archive

  defp document(questions \\ []) do
    %{"format_version" => 1, "title" => "Film Night", "questions" => questions}
  end

  defp zip(entries) do
    {:ok, {_name, binary}} =
      :zip.create(~c"test.fazoura", for({name, data} <- entries, do: {to_charlist(name), data}), [
        :memory
      ])

    binary
  end

  describe "round trip" do
    test "a package reads back as the document and photos it was built from" do
      photos = %{"media/still.png" => "not really a png, but bytes are bytes"}

      {:ok, binary} =
        Archive.build(document([%{"image" => %{"path" => "media/still.png"}}]), photos)

      assert {:ok, package} = Archive.read(binary)
      assert package.document == document([%{"image" => %{"path" => "media/still.png"}}])
      assert package.photos == photos
    end

    test "a package with no photos carries only its manifest" do
      {:ok, binary} = Archive.build(document(), %{})

      assert {:ok, %{document: document, photos: photos}} = Archive.read(binary)
      assert document["title"] == "Film Night"
      assert photos == %{}
    end

    test "media_path is where build puts a photo and the manifest points" do
      assert Archive.media_path("5b0e4f1c.jpg") == "media/5b0e4f1c.jpg"
    end
  end

  describe "refusals" do
    test "a file that is not a ZIP at all" do
      assert Archive.read("PK, honest") == {:error, :invalid_archive}
      assert Archive.read(<<0, 1, 2, 3>>) == {:error, :invalid_archive}
      assert Archive.read(:not_a_binary) == {:error, :invalid_archive}
    end

    test "a ZIP with no manifest" do
      assert zip([{"media/still.png", "bytes"}]) |> Archive.read() ==
               {:error, :manifest_missing}
    end

    test "a manifest that is not JSON" do
      assert zip([{"manifest.json", "{not json"}]) |> Archive.read() ==
               {:error, :manifest_invalid}
    end

    test "a manifest with no quiz in it" do
      # The document lives under `quiz` so the manifest has somewhere to grow; a bare
      # document at the top level is an older shape we never wrote.
      assert zip([{"manifest.json", Jason.encode!(%{"title" => "Film Night"})}])
             |> Archive.read() == {:error, :manifest_invalid}

      assert zip([{"manifest.json", Jason.encode!(%{"quiz" => "a string"})}])
             |> Archive.read() == {:error, :manifest_invalid}
    end

    test "a package larger than the limit is refused without being parsed" do
      assert :binary.copy(<<0>>, Archive.max_bytes() + 1) |> Archive.read() ==
               {:error, :archive_too_large}
    end

    test "a package that claims to expand into far more than it is" do
      # ~50 MB of zeros compresses to a few tens of kilobytes, so this sails past the
      # size check on the file itself. The central directory is what gives it away, and
      # it is read before a single byte is inflated.
      bomb = zip([{"media/big.png", :binary.copy(<<0>>, 50 * 1024 * 1024)}])

      assert byte_size(bomb) < Archive.max_bytes()
      assert Archive.read(bomb) == {:error, :archive_too_large}
    end
  end

  describe "what a package may carry" do
    test "anything outside media/ is left behind" do
      binary =
        zip([
          {"manifest.json", Jason.encode!(%{quiz: document()})},
          {"media/still.png", "kept"},
          {"README.txt", "dropped"},
          {"notes/thoughts.md", "dropped"}
        ])

      assert {:ok, %{photos: photos}} = Archive.read(binary)
      assert Map.keys(photos) == ["media/still.png"]
    end

    test "an entry whose name climbs out of the package never arrives" do
      binary =
        zip([
          {"manifest.json", Jason.encode!(%{quiz: document()})},
          {"media/../../../etc/passwd", "not your passwd"}
        ])

      # Two things have to go wrong for a name like that to matter, and neither can:
      # `:zip` drops it while unpacking (the log line below is its own), and nothing
      # here writes to disk in the first place.
      assert capture_log(fn ->
               assert {:ok, %{photos: photos}} = Archive.read(binary)
               assert photos == %{}
             end) =~ "Illegal path"
    end
  end
end

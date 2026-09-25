defmodule Fazoura.Quizzes.ArchiveTest do
  @moduledoc """
  The `.fazoura` container on its own (QUIZ_FORMAT.md §5.3b) — no database, no uploads.

  `read/1` is fed files from outside the server, so most of this is about what it does
  with ones that are not what they claim to be.
  """
  use ExUnit.Case, async: true

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

  # Rewrites every uncompressed-size field, in the central directory and the local
  # headers, to `size`: what a hand-built decompression bomb does.
  defp declare_sizes(binary, size) do
    binary
    |> patch_all(<<0x02014B50::little-32>>, 24, size)
    |> patch_all(<<0x04034B50::little-32>>, 22, size)
  end

  defp patch_all(binary, signature, field, value) do
    binary
    |> :binary.matches(signature)
    |> Enum.reduce(binary, fn {at, _}, acc ->
      skip = at + field
      <<head::binary-size(^skip), _old::little-32, tail::binary>> = acc
      <<head::binary, value::little-32, tail::binary>>
    end)
  end

  # `:zip` deflates everything; a stored entry is method 0, which other tools write
  # for photos that do not compress.
  defp stored_zip do
    entries = [
      {"manifest.json", Jason.encode!(%{quiz: document()})},
      {"media/a.png", "abc"}
    ]

    {locals, centrals, _offset} =
      Enum.reduce(entries, {[], [], 0}, fn {name, data}, {locals, centrals, offset} ->
        crc = :erlang.crc32(data)
        size = byte_size(data)

        fields =
          <<20::little-16, 0::16, 0::little-16, 0::32, crc::little-32, size::little-32,
            size::little-32, byte_size(name)::little-16, 0::16>>

        local = <<0x04034B50::little-32, fields::binary, name::binary, data::binary>>

        central =
          <<0x02014B50::little-32, 20::little-16, fields::binary, 0::16, 0::16, 0::16, 0::32,
            offset::little-32, name::binary>>

        {[local | locals], [central | centrals], offset + byte_size(local)}
      end)

    body = locals |> Enum.reverse() |> IO.iodata_to_binary()
    directory = centrals |> Enum.reverse() |> IO.iodata_to_binary()

    body <>
      directory <>
      <<0x06054B50::little-32, 0::16, 0::16, length(entries)::little-16,
        length(entries)::little-16, byte_size(directory)::little-32, byte_size(body)::little-32,
        0::16>>
  end

  defp deflate_zeros(bytes, chunk_bytes \\ 1024 * 1024) do
    z = :zlib.open()
    :zlib.deflateInit(z, :best_compression, :deflated, -15, 8, :default)
    chunk = :binary.copy(<<0>>, chunk_bytes)

    body =
      Enum.reduce(1..div(bytes, chunk_bytes), [], fn _, acc -> [acc, :zlib.deflate(z, chunk)] end)

    finish = :zlib.deflate(z, <<>>, :finish)
    :zlib.deflateEnd(z)
    :zlib.close(z)
    IO.iodata_to_binary([body, finish])
  end

  defp handmade_zip(name, compressed, uncompressed) do
    name_len = byte_size(name)
    comp_size = byte_size(compressed)

    local =
      <<0x50, 0x4B, 0x03, 0x04, 20::little-16, 0::little-16, 8::little-16, 0::little-16,
        0::little-16, 0::little-32, comp_size::little-32, uncompressed::little-32,
        name_len::little-16, 0::little-16>> <> name <> compressed

    central =
      <<0x50, 0x4B, 0x01, 0x02, 20::little-16, 20::little-16, 0::little-16, 8::little-16,
        0::little-16, 0::little-16, 0::little-32, comp_size::little-32, uncompressed::little-32,
        name_len::little-16, 0::little-16, 0::little-16, 0::little-16, 0::little-16, 0::little-32,
        0::little-32>> <> name

    eocd =
      <<0x50, 0x4B, 0x05, 0x06, 0::little-16, 0::little-16, 1::little-16, 1::little-16,
        byte_size(central)::little-32, byte_size(local)::little-32, 0::little-16>>

    local <> central <> eocd
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

    test "a package that lies about how much it expands to" do
      # The same bomb, with every size field rewritten to claim one byte. `:zip.unzip`
      # inflated entries like this to their full size regardless; the declared size is
      # now the most an entry may inflate to.
      bomb =
        zip([
          {"manifest.json", Jason.encode!(%{quiz: document()})},
          {"media/big.png", :binary.copy(<<0>>, 50 * 1024 * 1024)}
        ])
        |> declare_sizes(1)

      assert Archive.read(bomb) == {:error, :archive_too_large}
    end

    test "an entry whose contents do not match its checksum" do
      binary = zip([{"manifest.json", Jason.encode!(%{quiz: document()})}])
      [{at, _}] = :binary.matches(binary, <<0x02014B50::little-32>>)
      skip = at + 16
      <<head::binary-size(^skip), crc::little-32, tail::binary>> = binary
      corrupt = <<head::binary, crc + 1::little-32, tail::binary>>

      assert Archive.read(corrupt) == {:error, :invalid_archive}
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
      # the reader drops it, and nothing here writes to disk in the first place.
      assert {:ok, %{photos: photos}} = Archive.read(binary)
      assert photos == %{}
    end

    test "a package of stored (uncompressed) entries reads too" do
      assert {:ok, %{photos: %{"media/a.png" => "abc"}}} = Archive.read(stored_zip())
    end

    test "a member that lies about its uncompressed size over a deflate bomb is refused" do
      # `:zip.create` writes honest sizes, so we build the ZIP ourselves: a member that
      # declares 64 uncompressed bytes in both its headers over a stream that really
      # expands to 128 MB of zeros. The declared size is what a total-declared-size gate
      # would trust; the reader ignores it and counts what it actually inflates, so the
      # bomb is stopped at the ceiling. It never materialises: the whole file we hold is
      # under a megabyte, and inflation is aborted once the output passes 48 MB — which is
      # why reading a 128 MB expansion returns cleanly instead of exhausting memory.
      compressed = deflate_zeros(128 * 1024 * 1024)
      bomb = handmade_zip("media/bomb.png", compressed, 64)

      assert byte_size(bomb) < 1024 * 1024
      assert Archive.read(bomb) == {:error, :archive_too_large}
    end

    test "a package with a flood of tiny entries is refused" do
      # Walking a member list is itself work, so a package that carries more entries than
      # any honest quiz could is turned away before any of them is read.
      entries =
        [{"manifest.json", Jason.encode!(%{quiz: document()})}] ++
          for(i <- 1..3000, do: {"media/#{i}.png", "x"})

      assert entries |> zip() |> Archive.read() == {:error, :archive_too_large}
    end
  end
end

defmodule Fazoura.Quizzes.Archive do
  @moduledoc """
  The portable `.fazoura` package: a ZIP holding `manifest.json` and the photos its
  questions name under `media/` (protocol/QUIZ_FORMAT.md §5.3b).

  Both directions live here so they cannot drift. `build/2` is what
  `GET /api/quizzes/:id/archive` sends and what `tools/fazoura-cli/fazoura quiz pack` writes from a
  folder; `read/1` is what an admin upload takes back apart.

  `read/1` is the untrusted direction and treats the file as hostile. Publishing sends a
  package to `POST /api/quizzes` before anybody has looked at it, so `read/1` is effectively
  remote-unauthenticated attack surface, and a decompression bomb here would take out every
  live game. It defends in depth:

    * the whole file is capped at `@max_bytes` before it is touched;
    * the ZIP may hold at most `@max_entries` members, so a flood of tiny entries is refused
      before any of them is read;
    * **every member is inflated through a running output counter and aborted the moment the
      total passes `@max_unpacked_bytes`** — the ceiling is on the bytes we actually produce,
      never on what the central directory *claims*, so a member that under-declares its size
      over a real deflate bomb ("a lying bomb") cannot get past it, and memory stays bounded
      to roughly the ceiling rather than to whatever the stream expands to;
    * only `manifest.json` and legal `media/` entries are inflated at all, and a name that
      climbs out of the package (a `..` segment or an absolute path) is dropped rather than
      followed — the entries only ever live in memory, so such a name is a map key and
      nothing more.
  """

  @manifest "manifest.json"
  @media "media/"

  # The same ceiling `POST /api/rooms` puts on an inline quiz (QUIZ_FORMAT.md §5.8): the
  # two carry the same thing, a whole quiz with its photos.
  @max_bytes 32 * 1024 * 1024

  # What those bytes are allowed to become. Photos are already-compressed formats, so an
  # honest package barely shrinks and stays well under this; one that claims to expand
  # many times over is a decompression bomb.
  @max_unpacked_bytes 48 * 1024 * 1024

  # A quiz is at most 1024 questions (QUIZ_FORMAT.md §2.1), each carrying at most one photo,
  # so an honest package is a manifest plus up to 1024 photos. This leaves generous headroom
  # for that and a stray readme, while stopping a member list so long that merely walking it
  # is the attack.
  @max_entries 2048

  # The end-of-central-directory signature (APPNOTE.TXT §4.3.16). The local-header
  # (`PK\x03\x04`) and central-header (`PK\x01\x02`) signatures are matched as literal bytes
  # inside the bitstring patterns below.
  @end_of_central_directory <<0x50, 0x4B, 0x05, 0x06>>

  # Compression methods we understand: stored and raw deflate. Anything else is refused.
  @method_stored 0
  @method_deflated 8

  @type reason ::
          :archive_too_large | :invalid_archive | :manifest_missing | :manifest_invalid
  @type package :: %{document: map(), photos: %{String.t() => binary()}}

  @doc "Largest package that will be read, in bytes."
  @spec max_bytes() :: pos_integer()
  def max_bytes, do: @max_bytes

  @doc "Where a photo stored under `key` sits inside a package."
  @spec media_path(String.t()) :: String.t()
  def media_path(key), do: @media <> key

  @doc """
  Packs a quiz document and its photos into a `.fazoura` binary.

  `photos` is keyed by the paths the document's `image.path` fields use, which is what
  `media_path/1` builds.
  """
  @spec build(map(), %{String.t() => binary()}) :: {:ok, binary()} | {:error, term()}
  def build(document, photos) do
    # The document goes *under* `quiz`, not at the top level: the manifest is a wrapper
    # so the format has somewhere to grow, and the app's own reader looks for it there.
    entries =
      [{String.to_charlist(@manifest), Jason.encode!(%{quiz: document})}] ++
        for {path, binary} <- Enum.sort(photos), do: {String.to_charlist(path), binary}

    case :zip.create(~c"quiz.fazoura", entries, [:memory]) do
      {:ok, {_name, binary}} -> {:ok, binary}
      {:error, _reason} = error -> error
    end
  end

  @doc """
  Takes a `.fazoura` binary apart into its quiz document and the photos it carries,
  keyed by their path inside the package.

  The photos are returned rather than stored: whether they become uploads is the
  caller's business (`Fazoura.Quizzes.read_archive/1`).
  """
  @spec read(binary()) :: {:ok, package()} | {:error, reason()}
  def read(binary) when is_binary(binary) and byte_size(binary) > @max_bytes,
    do: {:error, :archive_too_large}

  def read(binary) when is_binary(binary) do
    with {:ok, entries} <- entries(binary),
         {:ok, contents} <- inflate(binary, entries),
         {:ok, document} <- manifest(contents) do
      {:ok, %{document: document, photos: media(contents)}}
    end
  end

  def read(_binary), do: {:error, :invalid_archive}

  # --- reading the ZIP ourselves ---------------------------------------------------------
  #
  # We do not hand the file to `:zip.unzip`: that inflates every member in full with no
  # output ceiling, and no `catch` can undo an out-of-memory. So we parse the container
  # (`entries/1`) and stream each member's deflate bytes through `:zlib.safeInflate/2`,
  # counting the output as it comes (`inflate/2`) and stopping the instant the total passes
  # the ceiling.

  # The central directory is the authoritative list of members. We find it through the
  # end-of-central-directory record at the tail, then walk it, capping the count.
  defp entries(binary) do
    safely(fn ->
      case central_directory_offset(binary) do
        {:ok, offset} -> collect_central(binary, offset, [], 0)
        :error -> {:error, :invalid_archive}
      end
    end)
  end

  # The end-of-central-directory record sits at the tail, behind a comment of at most 65_535
  # bytes, so it lies within the final 22 + 65_535 bytes and nowhere else. Searching only
  # that window keeps the match list bounded, so a file padded with fake signatures cannot
  # turn the scan into its own attack. Its signature can occur inside data too, so we take
  # the last match whose trailing comment length actually accounts for the bytes after it.
  defp central_directory_offset(binary) do
    size = byte_size(binary)
    base = max(0, size - (22 + 0xFFFF))
    window = binary_part(binary, base, size - base)

    window
    |> :binary.matches(@end_of_central_directory)
    |> Enum.reverse()
    |> Enum.find_value(:error, fn {pos, _len} -> end_of_central(binary, base + pos) end)
  end

  # The candidate at `offset` is the real end-of-central-directory record only when its
  # declared comment length accounts for exactly the bytes trailing it; a stray signature
  # inside the data fails that and the scan moves on.
  defp end_of_central(binary, offset) do
    case binary do
      <<_::binary-size(^offset), _sig::binary-size(4), _disk::little-16, _cd_disk::little-16,
        _here::little-16, _total::little-16, _cd_size::little-32, cd_offset::little-32,
        comment_len::little-16, comment::binary>> ->
        if byte_size(comment) == comment_len, do: {:ok, cd_offset}, else: false

      _other ->
        false
    end
  end

  defp collect_central(binary, offset, acc, count) do
    case binary do
      <<_::binary-size(^offset), 0x50, 0x4B, 0x01, 0x02, _vmade::16, _vneed::16,
        _flags::little-16, method::little-16, _mtime::16, _mdate::16, _crc::little-32,
        comp_size::little-32, _uncomp::little-32, name_len::little-16, extra_len::little-16,
        comment_len::little-16, _disk::16, _iattr::16, _eattr::32, local_offset::little-32,
        tail::binary>> ->
        if count >= @max_entries do
          {:error, :archive_too_large}
        else
          <<name::binary-size(^name_len), _::binary>> = tail

          entry = %{
            name: name,
            method: method,
            comp_size: comp_size,
            local_offset: local_offset
          }

          next = offset + 46 + name_len + extra_len + comment_len
          collect_central(binary, next, [entry | acc], count + 1)
        end

      # Anything that is not another central-directory header — the end record, padding, the
      # tail of the file — ends the walk.
      _other ->
        {:ok, Enum.reverse(acc)}
    end
  end

  # Inflate the members we keep, threading a cumulative output total through them all so the
  # ceiling is on the whole package, not on any one member. The zlib stream is opened once
  # and reset per member (each is an independent raw-deflate stream).
  defp inflate(binary, entries) do
    z = :zlib.open()
    :zlib.inflateInit(z, -15)

    try do
      safely(fn -> do_inflate(binary, z, entries) end)
    after
      :zlib.close(z)
    end
  end

  defp do_inflate(binary, z, entries) do
    entries
    |> Enum.reduce_while({:ok, %{}, 0}, fn entry, acc -> inflate_entry(binary, z, entry, acc) end)
    |> case do
      {:ok, contents, _total} -> {:ok, contents}
      {:error, _reason} = error -> error
    end
  end

  # One member: inflated and added to the running total when we keep it, skipped otherwise.
  # A member over the ceiling halts the whole reduction with its error.
  defp inflate_entry(binary, z, entry, {:ok, contents, total}) do
    if keep?(entry.name) do
      case member(binary, z, entry, total) do
        {:ok, data, new_total} -> {:cont, {:ok, Map.put(contents, entry.name, data), new_total}}
        {:error, _reason} = error -> {:halt, error}
      end
    else
      {:cont, {:ok, contents, total}}
    end
  end

  # We only ever inflate what we use: the manifest and the photos under `media/`. Everything
  # else a package might carry (a readme, an editor's leftovers) is left compressed, so a
  # bomb hidden in one is never expanded. A name that climbs out — a `..` segment or an
  # absolute path — is dropped even under `media/`, because `media/../..` still starts with
  # the prefix.
  defp keep?(name) do
    (name == @manifest or String.starts_with?(name, @media)) and not climbs_out?(name)
  end

  defp climbs_out?(name) do
    String.starts_with?(name, "/") or ".." in String.split(name, "/")
  end

  # Locate the member's compressed bytes from its local header (whose name/extra lengths give
  # the data offset), then inflate under the ceiling. The compressed length comes from the
  # central directory; nothing here trusts the declared *uncompressed* size.
  defp member(binary, z, %{local_offset: offset, comp_size: comp_size, method: method}, total) do
    <<_::binary-size(^offset), 0x50, 0x4B, 0x03, 0x04, _::binary-size(22), name_len::little-16,
      extra_len::little-16, _::binary>> = binary

    data = binary_part(binary, offset + 30 + name_len + extra_len, comp_size)
    expand(method, z, data, total)
  end

  # Stored members are already their own bytes; still counted against the ceiling.
  defp expand(@method_stored, _z, data, total) do
    new_total = total + byte_size(data)

    if new_total > @max_unpacked_bytes do
      {:error, :archive_too_large}
    else
      {:ok, data, new_total}
    end
  end

  defp expand(@method_deflated, z, data, total) do
    :zlib.inflateReset(z)
    stream(z, :zlib.safeInflate(z, data), [], total)
  end

  defp expand(_method, _z, _data, _total), do: {:error, :invalid_archive}

  # `safeInflate` yields a bounded chunk at a time, so we add each to the running total and
  # bail the moment it passes the ceiling — a bomb never has its full output materialised.
  defp stream(z, {status, output}, acc, total) do
    new_total = total + IO.iodata_length(output)

    cond do
      new_total > @max_unpacked_bytes ->
        {:error, :archive_too_large}

      status == :continue ->
        stream(z, :zlib.safeInflate(z, []), [output | acc], new_total)

      status == :finished ->
        {:ok, IO.iodata_to_binary(Enum.reverse([output | acc])), new_total}
    end
  end

  defp manifest(contents) do
    case Map.fetch(contents, @manifest) do
      {:ok, raw} -> decode_manifest(raw)
      :error -> {:error, :manifest_missing}
    end
  end

  defp decode_manifest(raw) do
    case Jason.decode(raw) do
      {:ok, %{"quiz" => %{} = document}} -> {:ok, document}
      _other -> {:error, :manifest_invalid}
    end
  end

  # `keep?/1` already dropped any climbing name, so `contents` holds only the manifest and
  # legal `media/` entries; this prefix filter leaves the manifest behind and keeps the rest.
  defp media(contents) do
    for {name, binary} <- contents, String.starts_with?(name, @media), into: %{} do
      {name, binary}
    end
  end

  # Parsing a file from outside means pattern matches and `:zlib` calls that raise on damage
  # they do not recognise. A raise here is just a malformed archive; a real ceiling breach
  # returns `{:error, :archive_too_large}` and passes straight through.
  defp safely(fun) do
    fun.()
  catch
    _kind, _value -> {:error, :invalid_archive}
  end
end

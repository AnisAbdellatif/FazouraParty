defmodule Fazoura.Quizzes.Archive do
  @moduledoc """
  The portable `.fazoura` package: a ZIP holding `manifest.json` and the photos its
  questions name under `media/` (protocol/QUIZ_FORMAT.md §5.3b).

  Both directions live here so they cannot drift. `build/2` is what
  `GET /api/quizzes/:id/archive` sends and what `tools/fazoura-cli/fazoura quiz pack` writes from a
  folder; `read/1` is what an admin upload takes back apart.

  `read/1` is the untrusted direction and treats the file as hostile. It does not use
  `:zip.unzip`, which inflates an entry until its compressed data runs out whatever size
  the file declares — so a 32 MB package declaring a byte per entry became 32 GB in
  memory. It walks the central directory itself instead, refuses a package whose declared
  sizes add up to more than a quiz could need, and inflates each entry under a cap of its
  own declared size, stopping the moment the output would pass it. The entries only ever
  live in memory, and a name carrying `..` or an absolute path is dropped.
  """

  import Bitwise

  @manifest "manifest.json"
  @media "media/"

  # The same ceiling `POST /api/rooms` puts on an inline quiz (QUIZ_FORMAT.md §5.8): the
  # two carry the same thing, a whole quiz with its photos.
  @max_bytes 32 * 1024 * 1024

  # What those bytes are allowed to become. Photos are already-compressed formats, so an
  # honest package barely shrinks and stays well under this; one that claims to expand
  # many times over is a decompression bomb.
  @max_unpacked_bytes 48 * 1024 * 1024

  # An honest package is a manifest and one photo per question; a quiz has at most a
  # few hundred questions. Far more entries than that is a file built to make the
  # directory walk itself expensive.
  @max_entries 2_000

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
    with {:ok, directory} <- central_directory(binary),
         :ok <- check_unpacked_size(directory),
         {:ok, entries} <- inflate_all(binary, directory),
         {:ok, document} <- manifest(entries) do
      {:ok, %{document: document, photos: media(entries)}}
    end
  end

  def read(_binary), do: {:error, :invalid_archive}

  ## Reading a ZIP (APPNOTE.TXT §4.3), with nothing trusted that is not checked

  @eocd_signature 0x06054B50
  @central_signature 0x02014B50
  @local_signature 0x04034B50
  @eocd_size 22
  # The end record is followed by a comment of at most 65,535 bytes.
  @eocd_search @eocd_size + 0xFFFF

  defp central_directory(binary) do
    with {:ok, count, size, offset} <- end_record(binary),
         true <- count <= @max_entries || {:error, :archive_too_large},
         true <- offset + size <= byte_size(binary) || {:error, :invalid_archive} do
      binary |> binary_part(offset, size) |> central_entries(count, [])
    end
  end

  defp end_record(binary) do
    window = min(byte_size(binary), @eocd_search)
    tail = binary_part(binary, byte_size(binary) - window, window)

    tail
    |> :binary.matches(<<@eocd_signature::little-32>>)
    |> List.last()
    |> case do
      {at, _length} when window - at >= @eocd_size ->
        <<_signature::32, disk::little-16, cd_disk::little-16, _here::little-16, count::little-16,
          size::little-32, offset::little-32, _comment::binary>> =
          binary_part(tail, at, window - at)

        # Split archives, and ZIP64's 0xFFFF / 0xFFFFFFFF markers: nothing this app
        # writes is either, and a 32 MB package never needs to be.
        if disk == 0 and cd_disk == 0 and count != 0xFFFF and offset != 0xFFFFFFFF,
          do: {:ok, count, size, offset},
          else: {:error, :invalid_archive}

      _other ->
        {:error, :invalid_archive}
    end
  end

  defp central_entries(_rest, 0, acc), do: {:ok, Enum.reverse(acc)}

  defp central_entries(
         <<@central_signature::little-32, _made_by::16, _needed::16, flags::little-16,
           method::little-16, _time::16, _date::16, crc::little-32, compressed::little-32,
           size::little-32, name_length::little-16, extra_length::little-16,
           comment_length::little-16, _disk::16, _internal::16, _external::32, offset::little-32,
           name::binary-size(name_length), _extra::binary-size(extra_length),
           _comment::binary-size(comment_length), rest::binary>>,
         count,
         acc
       ) do
    entry = %{
      name: name,
      flags: flags,
      method: method,
      crc: crc,
      compressed: compressed,
      size: size,
      offset: offset
    }

    central_entries(rest, count - 1, [entry | acc])
  end

  defp central_entries(_rest, _count, _acc), do: {:error, :invalid_archive}

  defp check_unpacked_size(directory) do
    total = directory |> Enum.map(& &1.size) |> Enum.sum()
    if total <= @max_unpacked_bytes, do: :ok, else: {:error, :archive_too_large}
  end

  defp inflate_all(binary, directory) do
    Enum.reduce_while(directory, {:ok, %{}}, fn entry, {:ok, entries} ->
      case take_entry(binary, entry, entries) do
        {:ok, entries} -> {:cont, {:ok, entries}}
        {:error, _reason} = error -> {:halt, error}
      end
    end)
  end

  defp take_entry(binary, entry, entries) do
    cond do
      not safe_name?(entry.name) ->
        {:ok, entries}

      Map.has_key?(entries, entry.name) ->
        {:error, :invalid_archive}

      true ->
        with {:ok, data} <- entry_data(binary, entry),
             do: {:ok, Map.put(entries, entry.name, data)}
    end
  end

  # Folders, and any name that could mean somewhere else were it ever written out.
  defp safe_name?(name) do
    String.valid?(name) and not String.ends_with?(name, "/") and
      not String.starts_with?(name, ["/", "\\"]) and
      not String.contains?(name, ["\\", <<0>>]) and
      ".." not in String.split(name, "/")
  end

  # Bit 0 is encryption; nothing here could read an encrypted entry anyway.
  defp entry_data(_binary, %{flags: flags}) when (flags &&& 1) == 1,
    do: {:error, :invalid_archive}

  defp entry_data(binary, entry) do
    with {:ok, compressed} <- compressed_data(binary, entry),
         {:ok, data} <- decompress(entry.method, compressed, entry.size),
         true <- byte_size(data) == entry.size || {:error, :invalid_archive},
         true <- :erlang.crc32(data) == entry.crc || {:error, :invalid_archive} do
      {:ok, data}
    end
  end

  # The local header repeats the name and carries its own extra field, so the data
  # starts wherever that header says — but how much of it there is comes from the
  # central directory, which is what was size-checked.
  defp compressed_data(binary, %{offset: offset, compressed: compressed}) do
    with true <- offset + 30 <= byte_size(binary) || {:error, :invalid_archive},
         <<@local_signature::little-32, _rest::binary-size(22), name_length::little-16,
           extra_length::little-16>> <- binary_part(binary, offset, 30),
         start = offset + 30 + name_length + extra_length,
         true <- start + compressed <= byte_size(binary) || {:error, :invalid_archive} do
      {:ok, binary_part(binary, start, compressed)}
    else
      {:error, _reason} = error -> error
      _other -> {:error, :invalid_archive}
    end
  end

  # Stored.
  defp decompress(0, data, _limit), do: {:ok, data}

  # Deflated: raw deflate (no zlib header), inflated a chunk at a time and abandoned
  # the moment it would come to more than the entry declared.
  defp decompress(8, data, limit) do
    z = :zlib.open()

    try do
      :ok = :zlib.inflateInit(z, -15)
      inflate(z, :zlib.safeInflate(z, data), limit, [], 0)
    catch
      _kind, _value -> {:error, :invalid_archive}
    after
      :zlib.close(z)
    end
  end

  defp decompress(_method, _data, _limit), do: {:error, :invalid_archive}

  defp inflate(z, {status, output}, limit, acc, total) do
    total = total + IO.iodata_length(output)

    cond do
      total > limit -> {:error, :archive_too_large}
      status == :finished -> {:ok, IO.iodata_to_binary(Enum.reverse([output | acc]))}
      true -> inflate(z, :zlib.safeInflate(z, []), limit, [output | acc], total)
    end
  end

  defp manifest(entries) do
    case Map.fetch(entries, @manifest) do
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

  # Anything outside `media/` is dropped: a package may carry a readme or an editor's
  # leftovers, and nothing else here is interested in them.
  defp media(entries) do
    for {name, binary} <- entries, String.starts_with?(name, @media), into: %{} do
      {name, binary}
    end
  end
end

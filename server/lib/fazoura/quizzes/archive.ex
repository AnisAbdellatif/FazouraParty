defmodule Fazoura.Quizzes.Archive do
  @moduledoc """
  The portable `.fazoura` package: a ZIP holding `manifest.json` and the photos its
  questions name under `media/` (protocol/QUIZ_FORMAT.md §5.3b).

  Both directions live here so they cannot drift. `build/2` is what
  `GET /api/quizzes/:id/archive` sends and what `tools/fazoura-cli/fazoura quiz pack` writes from a
  folder; `read/1` is what an admin upload takes back apart.

  `read/1` is the untrusted direction and treats the file as hostile. The package is
  capped, what it *claims* to expand to is checked against the central directory before a
  byte is inflated, and the entries only ever live in memory — so a name carrying `..` or
  an absolute path is a map key and nothing more.
  """

  require Record

  Record.defrecordp(:zip_file, Record.extract(:zip_file, from_lib: "stdlib/include/zip.hrl"))

  Record.defrecordp(
    :file_info,
    Record.extract(:file_info, from_lib: "kernel/include/file.hrl")
  )

  @manifest "manifest.json"
  @media "media/"

  # The same ceiling `POST /api/rooms` puts on an inline quiz (QUIZ_FORMAT.md §5.8): the
  # two carry the same thing, a whole quiz with its photos.
  @max_bytes 32 * 1024 * 1024

  # What those bytes are allowed to become. Photos are already-compressed formats, so an
  # honest package barely shrinks and stays well under this; one that claims to expand
  # many times over is a decompression bomb.
  @max_unpacked_bytes 48 * 1024 * 1024

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
    with :ok <- check_unpacked_size(binary),
         {:ok, entries} <- unzip(binary),
         {:ok, document} <- manifest(entries) do
      {:ok, %{document: document, photos: media(entries)}}
    end
  end

  def read(_binary), do: {:error, :invalid_archive}

  defp check_unpacked_size(binary) do
    case safely(fn -> :zip.list_dir(binary) end) do
      {:ok, listing} ->
        total =
          Enum.sum(
            for zip_file(info: file_info(size: size)) <- listing, is_integer(size), do: size
          )

        if total <= @max_unpacked_bytes, do: :ok, else: {:error, :archive_too_large}

      _other ->
        {:error, :invalid_archive}
    end
  end

  defp unzip(binary) do
    case safely(fn -> :zip.unzip(binary, [:memory]) end) do
      {:ok, entries} ->
        {:ok, Map.new(entries, fn {name, data} -> {List.to_string(name), data} end)}

      _other ->
        {:error, :invalid_archive}
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

  # `:zip` is an Erlang parser being handed a file from outside. It answers
  # `{:error, _}` for the damage it recognises and exits for the rest.
  defp safely(fun) do
    fun.()
  catch
    _kind, _value -> {:error, :invalid_archive}
  end
end

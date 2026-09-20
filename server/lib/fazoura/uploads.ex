defmodule Fazoura.Uploads do
  @moduledoc """
  Question photos on local disk, served at `/uploads/<key>`
  (protocol/QUIZ_FORMAT.md §5.6). The type is detected from the file content.
  """

  alias Fazoura.Uploads.Header

  @max_bytes 2 * 1024 * 1024

  @spec max_bytes() :: pos_integer()
  def max_bytes, do: @max_bytes

  @spec dir() :: String.t()
  def dir, do: Application.fetch_env!(:fazoura, :uploads_dir)

  @doc """
  Where a photo is served from, relative to whatever origin asked.

  What the dashboard's own HTML uses. `url/1` builds an absolute one from the endpoint's
  *public* URL, which is right for a quiz document a device on the other side of the
  internet will read, and wrong for a page already being served from this origin — behind
  a proxy, or in the local stack, that public URL is a different scheme and port.
  """
  @spec path(String.t()) :: String.t()
  def path(key), do: "/uploads/" <> key

  @spec url(String.t()) :: String.t()
  def url(key), do: FazouraWeb.Endpoint.url() <> path(key)

  @doc "Reads a previously stored upload by its generated key."
  @spec read(String.t()) :: {:ok, binary()} | :error
  def read(key) when is_binary(key) do
    case File.read(Path.join(dir(), Path.basename(key))) do
      {:ok, binary} -> {:ok, binary}
      {:error, _reason} -> :error
    end
  end

  def read(_key), do: :error

  @doc "Content type and file extension from the image's magic bytes."
  @spec detect(binary()) :: {:ok, String.t(), String.t()} | :error
  def detect(<<0xFF, 0xD8, 0xFF, _rest::binary>>), do: {:ok, "image/jpeg", "jpg"}

  def detect(<<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, _rest::binary>>),
    do: {:ok, "image/png", "png"}

  def detect(<<"RIFF", _size::binary-size(4), "WEBP", _rest::binary>>),
    do: {:ok, "image/webp", "webp"}

  def detect(_binary), do: :error

  @doc """
  Validates and writes the image; returns its new key.

  The type comes from the magic bytes and the header must then be structurally sound
  (`Fazoura.Uploads.Header`), so a file that merely starts like an image is refused
  before anything is written.
  """
  @spec store(binary()) ::
          {:ok, %{key: String.t(), content_type: String.t(), byte_size: non_neg_integer()}}
          | {:error, :image_too_large | :unsupported_image}
  def store(binary) when byte_size(binary) > @max_bytes, do: {:error, :image_too_large}

  def store(binary) when is_binary(binary) do
    with {:ok, content_type, ext} <- validate(binary) do
      key = Base.encode16(:crypto.strong_rand_bytes(12), case: :lower) <> "." <> ext
      File.mkdir_p!(dir())
      File.write!(Path.join(dir(), key), binary)
      {:ok, %{key: key, content_type: content_type, byte_size: byte_size(binary)}}
    end
  end

  @doc """
  Stores `binary` under a key derived from its own bytes, writing the file only when it
  is not already there.

  For photos that come from the repository rather than from a device (`priv/quizzes`,
  synced on every deploy): a random key would write a fresh copy each time and leave the
  previous one for the sweeper, so re-running a sync would churn the volume. Same bytes,
  same key, same file.
  """
  @spec store_stable(binary()) ::
          {:ok, %{key: String.t(), content_type: String.t(), byte_size: non_neg_integer()}}
          | {:error, :image_too_large | :unsupported_image}
  def store_stable(binary) when byte_size(binary) > @max_bytes, do: {:error, :image_too_large}

  def store_stable(binary) when is_binary(binary) do
    with {:ok, content_type, ext} <- validate(binary) do
      key = digest(binary) <> "." <> ext
      path = Path.join(dir(), key)

      unless File.regular?(path) do
        File.mkdir_p!(dir())
        File.write!(path, binary)
      end

      {:ok, %{key: key, content_type: content_type, byte_size: byte_size(binary)}}
    end
  end

  # The same shape as a generated key: 24 hex characters and an extension.
  defp digest(binary) do
    :crypto.hash(:sha256, binary) |> Base.encode16(case: :lower) |> binary_part(0, 24)
  end

  @doc """
  The content type and extension of a binary that is an image we accept, both by its
  magic bytes and by its header being well-formed and sanely sized.
  """
  @spec validate(binary()) :: {:ok, String.t(), String.t()} | {:error, :unsupported_image}
  def validate(binary) do
    with {:ok, content_type, ext} <- detect(binary),
         true <- Header.valid?(binary) do
      {:ok, content_type, ext}
    else
      _ -> {:error, :unsupported_image}
    end
  end
end

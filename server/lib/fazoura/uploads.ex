defmodule Fazoura.Uploads do
  @moduledoc """
  Question photos on local disk, served at `/uploads/<key>`
  (protocol/QUIZ_FORMAT.md §5.6). The type is detected from the file content.
  """

  @max_bytes 2 * 1024 * 1024

  @spec max_bytes() :: pos_integer()
  def max_bytes, do: @max_bytes

  @spec dir() :: String.t()
  def dir, do: Application.fetch_env!(:fazoura, :uploads_dir)

  @spec url(String.t()) :: String.t()
  def url(key), do: FazouraWeb.Endpoint.url() <> "/uploads/" <> key

  @doc "Content type and file extension from the image's magic bytes."
  @spec detect(binary()) :: {:ok, String.t(), String.t()} | :error
  def detect(<<0xFF, 0xD8, 0xFF, _rest::binary>>), do: {:ok, "image/jpeg", "jpg"}

  def detect(<<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, _rest::binary>>),
    do: {:ok, "image/png", "png"}

  def detect(<<"RIFF", _size::binary-size(4), "WEBP", _rest::binary>>),
    do: {:ok, "image/webp", "webp"}

  def detect(_binary), do: :error

  @doc "Validates and writes the image; returns its new key."
  @spec store(binary()) ::
          {:ok, %{key: String.t(), content_type: String.t(), byte_size: non_neg_integer()}}
          | {:error, :image_too_large | :unsupported_image}
  def store(binary) when byte_size(binary) > @max_bytes, do: {:error, :image_too_large}

  def store(binary) when is_binary(binary) do
    case detect(binary) do
      {:ok, content_type, ext} ->
        key = Base.encode16(:crypto.strong_rand_bytes(12), case: :lower) <> "." <> ext
        File.mkdir_p!(dir())
        File.write!(Path.join(dir(), key), binary)
        {:ok, %{key: key, content_type: content_type, byte_size: byte_size(binary)}}

      :error ->
        {:error, :unsupported_image}
    end
  end
end

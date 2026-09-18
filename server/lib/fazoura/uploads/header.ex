defmodule Fazoura.Uploads.Header do
  @moduledoc """
  Structural validation of an uploaded photo, from its header alone.

  Magic bytes say a file *starts* like an image; this says it is plausibly one. It reads
  the declared dimensions out of the format's own header and rejects anything absent,
  absurd or structurally malformed — which stops both "a JPEG header with a payload
  stapled to it" and a decompression bomb whose declared canvas would exhaust whatever
  eventually decodes it.

  **It deliberately does not decode.** No pixel data is touched and no image library is
  linked in, so the parsers with the ugliest CVE history (libwebp, libtiff, libpng) never
  run on this server. The client already downscales and re-encodes before upload, so a
  legitimate photo always has a sane header to read.

  Supports exactly the three types `Fazoura.Uploads.detect/1` accepts.
  """

  import Bitwise

  # Comfortably above the client's 1280 px longest side (QUIZ_FORMAT.md §5.6) and above
  # anything a phone camera produces, while far below a canvas that could exhaust a
  # decoder: 10000 x 10000 x 4 bytes is 400 MB, and we reject at that boundary.
  @max_dimension 10_000

  @type dimensions :: {pos_integer(), pos_integer()}

  @spec max_dimension() :: pos_integer()
  def max_dimension, do: @max_dimension

  @doc """
  Returns the image's declared dimensions, or `:error` if the header is not a
  well-formed one for its type or the dimensions are out of range.
  """
  @spec dimensions(binary()) :: {:ok, dimensions()} | :error
  def dimensions(<<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, rest::binary>>), do: png(rest)
  def dimensions(<<0xFF, 0xD8, 0xFF, rest::binary>>), do: jpeg(rest)

  def dimensions(<<"RIFF", size::little-32, "WEBP", rest::binary>>),
    do: webp(size, rest, byte_size(rest))

  def dimensions(_binary), do: :error

  @doc "Whether the header is well-formed and within the allowed dimensions."
  @spec valid?(binary()) :: boolean()
  def valid?(binary), do: match?({:ok, _dimensions}, dimensions(binary))

  ## PNG — the first chunk must be IHDR, which carries width and height.

  defp png(<<13::32, "IHDR", width::32, height::32, _rest::binary>>), do: check(width, height)
  defp png(_rest), do: :error

  ## JPEG — walk the marker segments to the start-of-frame, which carries the size.
  ##
  ## Markers are `FF xx`; most carry a 16-bit length. Anything else in the stream means
  ## the file is not a JPEG whatever its first three bytes claim.

  # Standalone markers (no payload): RSTn, SOI, TEM.
  defp jpeg(<<marker, rest::binary>>) when marker in 0xD0..0xD9, do: jpeg(rest)
  defp jpeg(<<0x01, rest::binary>>), do: jpeg(rest)

  # Fill bytes are legal padding between segments.
  defp jpeg(<<0xFF, rest::binary>>), do: jpeg(rest)

  # A start-of-frame: SOF0..SOF15, excluding DHT (C4), JPG (C8) and DAC (CC).
  defp jpeg(<<marker, length::16, _precision, height::16, width::16, _rest::binary>>)
       when marker in 0xC0..0xCF and marker not in [0xC4, 0xC8, 0xCC] and length >= 8,
       do: check(width, height)

  # Any other segment: skip its payload and continue. The length includes its own two
  # bytes, so a length under 2 is malformed and would not advance.
  defp jpeg(<<_marker, length::16, rest::binary>>) when length >= 2 do
    payload = length - 2

    case rest do
      <<_skipped::binary-size(^payload), 0xFF, next::binary>> -> jpeg(next)
      _ -> :error
    end
  end

  defp jpeg(_rest), do: :error

  ## WEBP — a RIFF container whose first chunk is VP8 (lossy), VP8L (lossless) or
  ## VP8X (extended). Each encodes its size differently, and all three are bit-packed.

  defp webp(size, rest, available) do
    # The RIFF size counts everything after it, so it must match what we actually have.
    if size == available + 4, do: webp_chunk(rest), else: :error
  end

  # Lossy: a 3-byte frame tag, the 3-byte start code 9D 01 2A, then 14-bit dimensions.
  defp webp_chunk(
         <<"VP8 ", _len::little-32, _tag::binary-size(3), 0x9D, 0x01, 0x2A, width::little-16,
           height::little-16, _rest::binary>>
       ) do
    # The top two bits of each are scaling hints, not part of the dimension.
    check(width &&& 0x3FFF, height &&& 0x3FFF)
  end

  # Lossless: signature 0x2F, then 14-bit width-1 and height-1 packed little-endian.
  defp webp_chunk(<<"VP8L", _len::little-32, 0x2F, bits::little-32, _rest::binary>>) do
    check((bits &&& 0x3FFF) + 1, (bits >>> 14 &&& 0x3FFF) + 1)
  end

  # Extended: flags and a reserved field, then 24-bit canvas width-1 and height-1.
  defp webp_chunk(
         <<"VP8X", _len::little-32, _flags::binary-size(4), width::little-24, height::little-24,
           _rest::binary>>
       ),
       do: check(width + 1, height + 1)

  defp webp_chunk(_rest), do: :error

  defp check(width, height)
       when width in 1..@max_dimension and height in 1..@max_dimension,
       do: {:ok, {width, height}}

  defp check(_width, _height), do: :error
end

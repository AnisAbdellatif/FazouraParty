defmodule Fazoura.Uploads.HeaderTest do
  @moduledoc """
  Structural validation stands between "starts with the right magic bytes" and "is
  plausibly an image". Each test here is a file that passed the magic-byte check and
  should not have.
  """

  use ExUnit.Case, async: true

  alias Fazoura.QuizFixtures
  alias Fazoura.Uploads
  alias Fazoura.Uploads.Header

  describe "real images" do
    test "a PNG's declared dimensions are read from IHDR" do
      assert Header.dimensions(QuizFixtures.png(640, 480)) == {:ok, {640, 480}}
    end

    test "a JPEG's dimensions are read from the start-of-frame" do
      assert {:ok, {1, 1}} = Header.dimensions(QuizFixtures.jpeg())
    end

    test "a lossless WEBP's dimensions are read from the VP8L chunk" do
      assert {:ok, {1, 1}} = Header.dimensions(QuizFixtures.webp())
    end

    test "a JPEG with segments before the frame is walked, not guessed" do
      # EXIF and comment segments sit between SOI and SOF; the parser has to skip them
      # by length rather than scanning for the first thing that looks like a frame.
      exif = <<0xFF, 0xE1, 0, 8, "Exif", 0, 0>>
      comment = <<0xFF, 0xFE, 0, 5, "abc">>
      # A start-of-frame stores height *before* width.
      sof = <<0xFF, 0xC0, 0, 11, 8, 200::16, 300::16, 1, 1, 0x11, 0>>
      jpeg = <<0xFF, 0xD8>> <> exif <> comment <> sof <> <<0xFF, 0xD9>>

      assert Header.dimensions(jpeg) == {:ok, {300, 200}}
    end
  end

  describe "fake images" do
    test "magic bytes with no header behind them are rejected" do
      for binary <- [
            <<0xFF, 0xD8, 0xFF>>,
            <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A>>,
            <<"RIFF", 0, 0, 0, 0, "WEBP">>
          ] do
        assert Header.dimensions(binary) == :error
        refute Header.valid?(binary)
      end
    end

    test "a payload stapled to a magic-byte prefix is rejected" do
      for payload <- ["<script>alert(1)</script>", <<0x7F, "ELF">>, "<?php system($c); ?>"] do
        assert Header.dimensions(<<0xFF, 0xD8, 0xFF>> <> payload) == :error
        assert Header.dimensions(<<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A>> <> payload) == :error
      end
    end

    test "a PNG whose first chunk is not IHDR is rejected" do
      not_ihdr = <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, 13::32, "IDAT", 0::64, 0::32>>

      assert Header.dimensions(not_ihdr) == :error
    end

    test "a WEBP whose RIFF size does not match its contents is rejected" do
      lying = <<"RIFF", 0xFFFFFFFF::little-32, "WEBP", "junk">>

      assert Header.dimensions(lying) == :error
    end

    test "a JPEG segment that overruns the file is rejected" do
      # Declares a 1000-byte segment in a file that has nothing like that left.
      truncated = <<0xFF, 0xD8, 0xFF, 0xE0, 1000::16, "short">>

      assert Header.dimensions(truncated) == :error
    end
  end

  describe "dimension limits" do
    test "a decompression bomb is refused on its declared size alone" do
      # 545 bytes on the wire, 3.6 GB if anything ever allocates its canvas.
      assert Header.dimensions(QuizFixtures.png(30_000, 30_000)) == :error
    end

    test "the boundary is exact" do
      max = Header.max_dimension()

      assert {:ok, {^max, ^max}} = Header.dimensions(QuizFixtures.png(max, max))
      assert Header.dimensions(QuizFixtures.png(max + 1, max)) == :error
      assert Header.dimensions(QuizFixtures.png(max, max + 1)) == :error
    end

    test "a zero dimension is not an image" do
      assert Header.dimensions(QuizFixtures.png(0, 10)) == :error
      assert Header.dimensions(QuizFixtures.png(10, 0)) == :error
    end
  end

  describe "Uploads.validate/1" do
    test "requires both the magic bytes and a sound header" do
      assert {:ok, "image/png", "png"} = Uploads.validate(QuizFixtures.png())

      assert Uploads.validate(<<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, "nope">>) ==
               {:error, :unsupported_image}

      assert Uploads.validate("GIF89a") == {:error, :unsupported_image}
    end

    test "a conformant image carrying arbitrary bytes is still accepted" do
      # Deliberate: stripping this would need a decoder. The response headers
      # (FazouraWeb.Plugs.UserContent) are what make it harmless.
      assert {:ok, "image/png", "png"} =
               Uploads.validate(QuizFixtures.png_with_text("<script>alert(1)</script>"))
    end
  end
end

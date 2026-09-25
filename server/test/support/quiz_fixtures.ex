defmodule Fazoura.QuizFixtures do
  @moduledoc "Test helpers for quizzes and packs."

  alias Fazoura.Game.Pack
  alias Fazoura.Quizzes.{Archive, Quiz, Review}
  alias Fazoura.Repo

  @doc """
  A preset in the database, made directly rather than from a file.

  Tests that only need "a built-in exists" used to call `Fazoura.Quizzes.sync_builtin!/0`
  and then reach for a slug by name, which tied the whole suite to whichever quizzes the
  repository happened to ship — removing one broke twenty tests that did not care about
  it. The two that are *about* loading from files build their own directory instead.
  """
  @spec builtin!(String.t(), map()) :: Quiz.t()
  def builtin!(slug, attrs \\ %{}) do
    %Quiz{
      slug: slug,
      source: "builtin",
      visibility: "public",
      questions: [],
      quiz_tags: []
    }
    |> Quiz.changeset(
      quiz_params(
        # Its own title and tags, distinct from the community quizzes the same tests
        # create, so a search or a tag filter can tell them apart.
        Map.merge(
          %{"title" => "General Knowledge", "tags" => ["general", "trivia", "classics"]},
          attrs
        )
      )
    )
    |> Repo.insert!()
  end

  @doc """
  A `.fazoura` package built from `quiz_params/1`.

  Publishing is a submission of one of these now (QUIZ_FORMAT.md §4), so this
  is what a test sends where it used to post a JSON document.
  """
  def package(attrs \\ %{}, photos \\ %{}) do
    {:ok, binary} = Archive.build(atomise(quiz_params(attrs)), photos)
    binary
  end

  @doc "The same, as the multipart file part the API takes."
  def package_upload(attrs \\ %{}, photos \\ %{}) do
    path =
      Path.join(System.tmp_dir!(), "fazoura-#{System.unique_integer([:positive])}.fazoura")

    File.write!(path, package(attrs, photos))
    %Plug.Upload{path: path, filename: "quiz.fazoura", content_type: "application/zip"}
  end

  @doc "Submits a package and approves it: a quiz that is actually live."
  def published!(attrs \\ %{}, key \\ owner_key()) do
    {:ok, submission} = Review.submit(package(attrs), key)
    {:ok, quiz} = Review.approve(submission.id)
    quiz
  end

  # `Archive.build/2` takes the document in the shape `to_document/2` produces.
  defp atomise(map) when is_map(map),
    do: Map.new(map, fn {k, v} -> {String.to_atom(k), atomise(v)} end)

  defp atomise(list) when is_list(list), do: Enum.map(list, &atomise/1)
  defp atomise(other), do: other

  def owner_key, do: "test-owner-key-aaaaaaaaaaaaaaaaaaaaaaaaaaaa"
  def other_key, do: "test-other-key-bbbbbbbbbbbbbbbbbbbbbbbbbbbb"

  @doc """
  A real, if tiny, PNG: 1x1 greyscale, built here rather than stubbed.

  Uploads are now checked structurally (`Fazoura.Uploads.Header`), so a fixture that is
  only a magic-byte prefix is rejected exactly like the fake images that check exists to
  stop. Tests therefore need something genuinely well-formed.
  """
  @spec png() :: binary()
  def png(width \\ 1, height \\ 1), do: png(width, height, "")

  defp png(width, height, extra) do
    header = <<width::32, height::32, 8, 0, 0, 0, 0>>

    <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A>> <>
      png_chunk("IHDR", header) <>
      png_chunk("IDAT", idat(width, height)) <>
      extra <>
      png_chunk("IEND", "")
  end

  # Real scanlines for a small image; for the large ones used to test dimension limits,
  # a token IDAT, since nothing on the server decodes pixels and generating hundreds of
  # megabytes to read an 8-byte header would only slow the suite down.
  defp idat(width, height) when width * height <= 10_000,
    do: :zlib.compress(:binary.copy(<<0>>, height * (width + 1)))

  defp idat(_width, _height), do: :zlib.compress(<<0>>)

  defp png_chunk(type, data) do
    payload = type <> data
    <<byte_size(data)::32>> <> payload <> <<:erlang.crc32(payload)::32>>
  end

  @doc """
  A valid PNG of at least `bytes` total, for tests about size limits.

  Grown with an ancillary chunk placed before IEND — where the spec allows one — rather
  than junk appended after it, so the file stays conformant and only its length varies.
  """
  @spec png_of_size(pos_integer()) :: binary()
  def png_of_size(bytes) do
    overhead = byte_size(png()) + 12
    # "tEXt" is ancillary (lower-case first letter), so any decoder may skip it.
    png(1, 1, png_chunk("tEXt", :binary.copy("p", max(bytes - overhead, 0))))
  end

  @doc """
  A photo as an inline quiz carries one: base64 of a real PNG of `bytes`.

  Uploads are validated structurally, so a magic-byte stub would be rejected by that
  check rather than by whatever limit a test is actually about.
  """
  @spec photo_data(pos_integer()) :: String.t()
  def photo_data(bytes), do: Base.encode64(png_of_size(bytes))

  @doc """
  A photo size every per-image check accepts, for tests about the per-room total.

  Half the per-image cap, so no single photo is ever what fails — which is the whole
  point of the tests that use it (QUIZ_FORMAT.md §5.7).
  """
  @spec under_image_cap() :: pos_integer()
  def under_image_cap, do: div(Fazoura.Uploads.max_bytes(), 2)

  @doc """
  A valid PNG carrying `text` in an ancillary chunk.

  Structural validation cannot reject this — it is a conformant image — which is what
  makes it the right fixture for testing the response headers that stop a browser
  treating the payload as markup.
  """
  @spec png_with_text(String.t()) :: binary()
  def png_with_text(text), do: png(1, 1, png_chunk("tEXt", text))

  @doc """
  A minimal JPEG: SOI, a start-of-frame declaring 1x1, then EOI.

  Enough to be structurally valid — which is all the server checks, since it never
  decodes — without embedding a real entropy-coded scan.
  """
  @spec jpeg() :: binary()
  def jpeg do
    # SOF0: length 17, 8-bit precision, 1x1, one component.
    sof = <<0xFF, 0xC0, 0, 11, 8, 1::16, 1::16, 1, 1, 0x11, 0>>
    <<0xFF, 0xD8>> <> <<0xFF, 0xE0, 0, 4, "JF">> <> sof <> <<0xFF, 0xD9>>
  end

  @doc "A minimal lossless WEBP (VP8L) declaring 1x1."
  @spec webp() :: binary()
  def webp do
    # VP8L: signature 0x2F then 14-bit (width-1) and (height-1), so 0 and 0 mean 1x1.
    chunk = <<"VP8L", 5::little-32, 0x2F, 0::little-32>>
    <<"RIFF", byte_size(chunk) + 4::little-32, "WEBP">> <> chunk
  end

  @doc "A small in-memory pack for room/channel tests that don't need the database."
  def pack do
    Pack.from_map(%{
      "title" => "General Knowledge",
      "questions" =>
        for i <- 1..3 do
          %{
            "id" => "q#{i}",
            "prompt" => "Question #{i}?",
            "accepted_answers" => ["Answer #{i}"],
            "time_limit_ms" => 30_000
          }
        end
    })
  end

  @doc "A valid quiz document (QUIZ_FORMAT.md §2) with string keys, as JSON decodes it."
  def quiz_params(attrs \\ %{}) do
    Map.merge(
      %{
        "format_version" => "1.0",
        "title" => "Movie Night",
        "tags" => ["movies", "cinema"],
        "questions" => [
          %{
            "type" => "text",
            "prompt" => "Who directed Jurassic Park?",
            "accepted_answers" => ["Steven Spielberg", "Spielberg"],
            "difficulty" => "easy"
          }
        ]
      },
      attrs
    )
  end
end

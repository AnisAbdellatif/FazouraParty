defmodule FazouraWeb.SecurityTest do
  @moduledoc """
  The limits and headers that keep anonymous, unauthenticated endpoints from costing the
  server more than they cost the caller.

  Room creation and photo upload need no account by design (AGENTS.md §5), so what bounds
  them is capacity and rate rather than identity. Each test here stands for a way the
  server was previously floodable or a way uploaded bytes could be mistaken for markup.
  """

  use FazouraWeb.ConnCase, async: false

  alias Fazoura.{QuizFixtures, Quizzes, RateLimit, Rooms}

  setup do
    QuizFixtures.builtin!("general-knowledge")
    :ok
  end

  # Real PNGs: uploads are validated structurally, so a magic-byte stub would be
  # rejected by that check rather than by the limit under test.
  defp photo(bytes), do: Base.encode64(QuizFixtures.png_of_size(bytes))

  defp inline_quiz(questions) do
    %{
      "quiz" => %{
        "format_version" => 1,
        "title" => "Inline",
        "tags" => ["test"],
        "questions" => questions
      }
    }
  end

  defp photo_question(index, bytes) do
    %{
      "type" => "text_photo",
      "prompt" => "Question #{index}?",
      "accepted_answers" => ["a"],
      "image" => %{"data" => photo(bytes)}
    }
  end

  describe "inline quiz size" do
    test "a quiz whose photos exceed the per-room total is refused", %{conn: conn} do
      # Each photo is comfortably under the 2 MB per-image cap; together they are over
      # the room cap. This is the case that used to be accepted and pin the memory for
      # ten minutes, and it must fail on the total rather than on any single image.
      questions = for i <- 1..count_over_cap(), do: photo_question(i, under_image_cap())

      conn = post(conn, ~p"/api/rooms", inline_quiz(questions))

      assert %{"code" => "quiz_too_large"} = json_response(conn, 413)
    end

    test "a quiz within the total is still accepted", %{conn: conn} do
      questions = [photo_question(1, 1000), photo_question(2, 1000)]

      assert %{"room_code" => _} =
               conn |> post(~p"/api/rooms", inline_quiz(questions)) |> json_response(201)
    end

    test "refusing one leaves no photos behind in memory", %{conn: conn} do
      before = :ets.info(Fazoura.Rooms.Images, :size)
      questions = for i <- 1..count_over_cap(), do: photo_question(i, under_image_cap())

      post(conn, ~p"/api/rooms", inline_quiz(questions))

      assert :ets.info(Fazoura.Rooms.Images, :size) == before
    end
  end

  # A photo size that every per-image check accepts, and how many of them it takes to
  # pass the per-room total.
  defp under_image_cap, do: div(Fazoura.Uploads.max_bytes(), 2)
  defp count_over_cap, do: ceil(Quizzes.max_inline_bytes() / under_image_cap()) + 1

  describe "room capacity" do
    test "creating a room past the cap is refused rather than accepted forever", %{conn: conn} do
      Application.put_env(:fazoura, :max_rooms, Rooms.count())
      on_exit(fn -> Application.delete_env(:fazoura, :max_rooms) end)

      conn = post(conn, ~p"/api/rooms", %{quiz_id: "general-knowledge"})

      assert %{"code" => "too_many_rooms"} = json_response(conn, 503)
    end

    test "capacity is counted, so rooms can be created again once some end", %{conn: conn} do
      Application.put_env(:fazoura, :max_rooms, Rooms.count() + 1)
      on_exit(fn -> Application.delete_env(:fazoura, :max_rooms) end)

      assert %{"room_code" => code} =
               conn |> post(~p"/api/rooms", %{quiz_id: "general-knowledge"}) |> json_response(201)

      assert %{"code" => "too_many_rooms"} =
               conn |> post(~p"/api/rooms", %{quiz_id: "general-knowledge"}) |> json_response(503)

      [{pid, _}] = Registry.lookup(Fazoura.Rooms.Registry, code)
      DynamicSupervisor.terminate_child(Fazoura.Rooms.Supervisor, pid)

      assert %{"room_code" => _} =
               conn |> post(~p"/api/rooms", %{quiz_id: "general-knowledge"}) |> json_response(201)
    end
  end

  describe "rate limiting" do
    setup do
      Application.put_env(:fazoura, :rate_limit_enabled, true)
      RateLimit.reset()

      on_exit(fn ->
        Application.put_env(:fazoura, :rate_limit_enabled, false)
        RateLimit.reset()
      end)
    end

    test "room creation is capped per caller", %{conn: conn} do
      # 20 per minute (router); the 21st is refused.
      for _ <- 1..20 do
        assert conn |> post(~p"/api/rooms", %{quiz_id: "general-knowledge"}) |> json_response(201)
      end

      conn = post(conn, ~p"/api/rooms", %{quiz_id: "general-knowledge"})

      assert %{"code" => "rate_limited"} = json_response(conn, 429)
      assert ["60"] = get_resp_header(conn, "retry-after")
    end

    test "publishing is capped per caller", %{conn: conn} do
      key = QuizFixtures.owner_key()
      conn = put_req_header(conn, "x-owner-key", key)

      for _ <- 1..30 do
        conn
        |> post(~p"/api/quizzes", %{"file" => QuizFixtures.package_upload()})
        |> json_response(201)
      end

      assert %{"code" => "rate_limited"} =
               conn
               |> post(~p"/api/quizzes", %{"file" => QuizFixtures.package_upload()})
               |> json_response(429)
    end

    test "archives are capped well below the other reads", %{conn: conn} do
      key = QuizFixtures.owner_key()

      # An archive is only offered for a quiz that is actually public, and a
      # quiz only becomes public through the queue (QUIZ_FORMAT.md §4).
      %{id: id} = QuizFixtures.published!(%{}, key)

      # Building one holds the whole quiz and every photo in memory, so 10 a
      # minute (router), not the unmetered rate the cheap reads get.
      for _ <- 1..10 do
        assert conn |> get(~p"/api/quizzes/#{id}/archive") |> response(200)
      end

      conn = get(conn, ~p"/api/quizzes/#{id}/archive")
      assert %{"code" => "rate_limited"} = json_response(conn, 429)
      assert ["60"] = get_resp_header(conn, "retry-after")
    end

    test "an archive flood leaves the ordinary reads alone", %{conn: conn} do
      for _ <- 1..11, do: get(conn, ~p"/api/quizzes/nope/archive")

      assert conn |> get(~p"/api/quizzes") |> json_response(200)
    end

    test "reads are not capped", %{conn: conn} do
      for _ <- 1..50 do
        assert conn |> get(~p"/api/quizzes") |> json_response(200)
      end
    end

    test "buckets are independent, so one flood doesn't lock the others", %{conn: conn} do
      for _ <- 1..21, do: post(conn, ~p"/api/rooms", %{quiz_id: "general-knowledge"})

      assert conn |> get(~p"/api/tags") |> json_response(200)
    end

    test "callers are counted separately" do
      limit = 3

      for _ <- 1..limit do
        assert RateLimit.check(:test, "1.1.1.1", limit, 60_000) == :ok
      end

      assert RateLimit.check(:test, "1.1.1.1", limit, 60_000) == {:error, :rate_limited}
      assert RateLimit.check(:test, "2.2.2.2", limit, 60_000) == :ok
    end

    test "behind a proxy, players are told apart by X-Forwarded-For", %{conn: conn} do
      # Without this every request arrives from the proxy's address, so one flood would
      # lock out the whole party. Production sets :trust_forwarded_for for exactly this.
      Application.put_env(:fazoura, :trust_forwarded_for, true)
      on_exit(fn -> Application.delete_env(:fazoura, :trust_forwarded_for) end)

      flood = fn ip ->
        for _ <- 1..21 do
          conn
          |> put_req_header("x-forwarded-for", ip)
          |> post(~p"/api/rooms", %{quiz_id: "general-knowledge"})
          |> Map.fetch!(:status)
        end
      end

      assert 429 in flood.("1.1.1.1")
      # A different player is unaffected by the first one's flood.
      refute 429 in Enum.take(flood.("2.2.2.2"), 20)
    end

    test "only the proxy's own entry of X-Forwarded-For is trusted", %{conn: conn} do
      Application.put_env(:fazoura, :trust_forwarded_for, true)
      on_exit(fn -> Application.delete_env(:fazoura, :trust_forwarded_for) end)

      # A client prepending its own values must not be able to pick a fresh bucket:
      # the proxy appends the real address last, so that is the one that counts.
      statuses =
        for spoof <- 1..21 do
          conn
          |> put_req_header("x-forwarded-for", "10.0.0.#{spoof}, 9.9.9.9")
          |> post(~p"/api/rooms", %{quiz_id: "general-knowledge"})
          |> Map.fetch!(:status)
        end

      assert 429 in statuses
    end
  end

  describe "user content headers" do
    test "an uploaded photo cannot be sniffed as anything but its declared type", %{conn: conn} do
      # Only the first bytes are checked when storing, so the tail of a valid image can
      # contain anything; these headers are what stop a browser acting on it.
      # A structurally valid PNG whose ancillary chunk carries markup: the header check
      # cannot object to it, which is exactly why the response headers matter.
      upload = %Plug.Upload{
        path: write_temp(QuizFixtures.png_with_text("<script>alert(1)</script>")),
        filename: "x.png",
        content_type: "image/png"
      }

      %{"key" => key} =
        conn
        |> put_req_header("x-owner-key", QuizFixtures.owner_key())
        |> post(~p"/api/images", %{"file" => upload})
        |> json_response(201)

      served = get(build_conn(), "/uploads/#{key}")

      assert served.status == 200
      assert ["nosniff"] = get_resp_header(served, "x-content-type-options")
      assert ["inline"] = get_resp_header(served, "content-disposition")
      assert ["sandbox; default-src 'none'"] = get_resp_header(served, "content-security-policy")
    end

    test "a private quiz's photo carries the same headers", %{conn: conn} do
      questions = [photo_question(1, 100)]
      assert conn |> post(~p"/api/rooms", inline_quiz(questions)) |> json_response(201)

      key = Fazoura.Rooms.Images |> :ets.tab2list() |> List.first() |> elem(0)
      served = get(build_conn(), ~p"/api/room-images/#{key}")

      assert served.status == 200
      assert ["nosniff"] = get_resp_header(served, "x-content-type-options")
      assert ["inline"] = get_resp_header(served, "content-disposition")
    end
  end

  describe "body size" do
    test "a large body is refused on routes that never need one", %{conn: conn} do
      # Which routes do need one, and why, is pinned in
      # `FazouraWeb.Plugs.BodyLimitTest`; this is the other half — that the small
      # default still bites everywhere else.
      conn =
        conn
        |> put_req_header("content-length", "2000000")
        |> put_req_header("x-owner-key", QuizFixtures.owner_key())
        |> post(~p"/api/submissions", %{})

      assert %{"code" => "payload_too_large"} = json_response(conn, 413)
    end

    test "room creation still accepts a whole inline quiz", %{conn: conn} do
      conn = put_req_header(conn, "content-length", "2000000")

      assert %{"room_code" => _} =
               conn
               |> post(~p"/api/rooms", inline_quiz([photo_question(1, 100)]))
               |> json_response(201)
    end
  end

  defp write_temp(binary) do
    path = Path.join(System.tmp_dir!(), "fazoura-test-#{System.unique_integer([:positive])}")
    File.write!(path, binary)
    on_exit(fn -> File.rm(path) end)
    path
  end
end

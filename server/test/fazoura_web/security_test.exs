defmodule FazouraWeb.SecurityTest do
  @moduledoc """
  The limits and headers that keep anonymous, unauthenticated endpoints from costing the
  server more than they cost the caller.

  Room creation and photo upload need no account by design (AGENTS.md §5), so what bounds
  them is capacity and rate rather than identity. Each test here stands for a way the
  server was previously floodable or a way uploaded bytes could be mistaken for markup.
  """

  use FazouraWeb.ConnCase, async: false

  import FazouraWeb.RoomJoin

  require Phoenix.ChannelTest

  alias Fazoura.{QuizFixtures, Quizzes, RateLimit, Repo, Rooms}
  alias Fazoura.Quizzes.Report
  alias Fazoura.Rooms.{Images, Limits}

  setup do
    QuizFixtures.builtin!("general-knowledge")
    :ok
  end

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
      "image" => %{"data" => QuizFixtures.photo_data(bytes)}
    }
  end

  describe "inline quiz size" do
    test "a quiz whose photos exceed the per-room total is refused", %{conn: conn} do
      # Each photo is comfortably under the 2 MB per-image cap; together they are over
      # the room cap. This is the case that used to be accepted and pin the memory for
      # ten minutes, and it must fail on the total rather than on any single image.
      questions =
        for i <- 1..count_over_cap(), do: photo_question(i, QuizFixtures.under_image_cap())

      conn = post(conn, ~p"/api/rooms", inline_quiz(questions))

      assert %{"code" => "quiz_too_large"} = json_response(conn, 413)
    end

    test "a quiz within the total is still accepted", %{conn: conn} do
      questions = [photo_question(1, 1000), photo_question(2, 1000)]

      assert %{"room_code" => _} =
               conn |> post(~p"/api/rooms", inline_quiz(questions)) |> json_response(201)
    end

    test "refusing one leaves no photos behind in memory", %{conn: conn} do
      before = Images.count()

      questions =
        for i <- 1..count_over_cap(), do: photo_question(i, QuizFixtures.under_image_cap())

      post(conn, ~p"/api/rooms", inline_quiz(questions))

      assert Images.count() == before
    end
  end

  # How many photos it takes to pass the per-room total, at a size no per-image check
  # objects to.
  defp count_over_cap, do: ceil(Quizzes.max_inline_bytes() / QuizFixtures.under_image_cap()) + 1

  describe "what one caller may hold" do
    setup do
      previous = Application.get_env(:fazoura, Limits)
      on_exit(fn -> Application.put_env(:fazoura, Limits, previous) end)
    end

    defp limit(opts) do
      current = Application.get_env(:fazoura, Limits, [])
      Application.put_env(:fazoura, Limits, Keyword.merge(current, opts))
    end

    test "one address holds only so many rooms, and gets them back as they end", %{conn: conn} do
      # Rooms live while anybody is in them, so the rate limit on creating them only
      # slowed a caller filling the node down; this is what stops it.
      limit(rooms_per_address: 2)
      # An address of its own: other tests' rooms all come from 127.0.0.1.
      conn = %{conn | remote_ip: {198, 51, 100, 7}}

      codes =
        for _ <- 1..2 do
          %{"room_code" => code} = conn |> post(~p"/api/rooms", %{}) |> json_response(201)
          code
        end

      assert %{"code" => "rate_limited"} =
               conn |> post(~p"/api/rooms", %{}) |> json_response(429)

      [{pid, _}] = Registry.lookup(Fazoura.Rooms.Registry, hd(codes))
      ref = Process.monitor(pid)
      DynamicSupervisor.terminate_child(Fazoura.Rooms.Supervisor, pid)
      assert_receive {:DOWN, ^ref, _, _, _}

      # The registry forgets an exited room on its own clock, not the test's.
      Enum.find_value(1..100, fn _ ->
        Limits.may_create?("198.51.100.7") || Process.sleep(10)
      end)

      assert conn |> post(~p"/api/rooms", %{}) |> json_response(201)
    end

    test "an IPv6 network is held to a wider allowance of its own" do
      # One /64 is a subscriber; a /48 is 65,536 of them.
      limit(rooms_per_address: 10, rooms_per_network: 2)

      hold = fn address ->
        test = self()

        spawn_link(fn ->
          :ok = Limits.created_by(address)
          send(test, :held)
          Process.sleep(:infinity)
        end)

        assert_receive :held
      end

      hold.("2001:db8:1:1::/64")
      hold.("2001:db8:1:2::/64")

      refute Limits.may_create?("2001:db8:1:3::/64")
      assert Limits.may_create?("2001:db8:2:1::/64")
      assert Limits.may_create?("203.0.113.9")
    end

    test "one connection is in only so many rooms at once" do
      limit(rooms_per_connection: 2)
      socket = Phoenix.ChannelTest.socket(FazouraWeb.UserSocket, nil, %{})

      codes =
        for _ <- 1..3 do
          {:ok, code, _token} = Rooms.create(QuizFixtures.pack())
          code
        end

      join = fn code ->
        Phoenix.ChannelTest.subscribe_and_join(socket, FazouraWeb.RoomChannel, "room:" <> code, %{
          "protocol_version" => Fazoura.Game.protocol_major(),
          "display_name" => "Sam"
        })
      end

      assert {:ok, _, _} = join.(Enum.at(codes, 0))
      assert {:ok, _, _} = join.(Enum.at(codes, 1))
      assert {:error, %{code: "rate_limited"}} = join.(Enum.at(codes, 2))
    end

    test "private-quiz photos are held to a total across every room", %{conn: conn} do
      # One room is held to its own cap; many rooms together are held to this, so a
      # flood of rooms full of photos is told the server is busy instead of the node
      # running out of memory.
      Application.put_env(:fazoura, :max_room_image_bytes, 1500)
      on_exit(fn -> Application.delete_env(:fazoura, :max_room_image_bytes) end)

      held = Images.total_bytes()
      Application.put_env(:fazoura, :max_room_image_bytes, held + 1500)

      assert conn
             |> post(~p"/api/rooms", inline_quiz([photo_question(1, 1000)]))
             |> json_response(201)

      assert %{"code" => "too_many_rooms"} =
               conn
               |> post(~p"/api/rooms", inline_quiz([photo_question(1, 1000)]))
               |> json_response(503)
    end
  end

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

    test "guessing room codes over the socket is cut off, joining is not" do
      {:ok, real, _token} = Rooms.create(QuizFixtures.pack())

      # An address of its own: tests running alongside join with none, and would be
      # counted against the same "unknown" as these guesses.
      join_room = fn code, payload ->
        FazouraWeb.UserSocket
        |> Phoenix.ChannelTest.socket(nil, %{ip_hash: "guesser"})
        |> Phoenix.ChannelTest.subscribe_and_join(
          FazouraWeb.RoomChannel,
          "room:" <> code,
          Map.put(payload, "protocol_version", Fazoura.Game.protocol_major())
        )
      end

      # Joins that work are never counted: a whole room, more than the limit, is fine.
      for n <- 1..32 do
        assert {:ok, _, _} = join_room.(real, %{"display_name" => "Player #{n}"})
      end

      # Guesses are. Codes are drawn from the room code alphabet, so none is `real`.
      for n <- 1..30 do
        guess = "ZZZZ" <> String.pad_leading(Integer.to_string(n, 32), 2, "2")
        assert {:error, %{code: "room_not_found"}} = join_room.(guess, %{"display_name" => "G"})
      end

      # Past the limit, even the real room is refused, so an answer says nothing.
      assert {:error, %{code: "rate_limited"}} = join_room.(real, %{"display_name" => "Late"})
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

    test "one channel may send only so many events" do
      {:ok, code, host_token} = Rooms.create(QuizFixtures.pack())
      {:ok, _, host} = join_room(code, %{"host_token" => host_token})

      # Choosing quizzes loads them from the database, so it has an allowance of its own.
      for _ <- 1..10 do
        ref = Phoenix.ChannelTest.push(host, "host_select_quiz", %{"quizzes" => []})
        Phoenix.ChannelTest.assert_reply(ref, :error, %{code: "invalid_quiz"})
      end

      ref = Phoenix.ChannelTest.push(host, "host_select_quiz", %{"quizzes" => []})
      Phoenix.ChannelTest.assert_reply(ref, :error, %{code: "rate_limited"})

      # Everything else has a wider one.
      for _ <- 1..49 do
        ref = Phoenix.ChannelTest.push(host, "host_pause", %{})
        Phoenix.ChannelTest.assert_reply(ref, :error, %{})
      end

      ref = Phoenix.ChannelTest.push(host, "host_pause", %{})
      Phoenix.ChannelTest.assert_reply(ref, :error, %{code: "rate_limited"})
    end

    test "one address may send only so many quizzes for review a day", %{conn: conn} do
      # A new publisher key every time, as somebody flooding the queue would send:
      # the key is theirs to make up, so the address is what is counted — and by the
      # day, since a queue nobody has read yet does not empty itself.
      as_new_device = fn n ->
        put_req_header(conn, "x-owner-key", String.pad_trailing("flood-key-#{n}-", 44, "x"))
      end

      for n <- 1..10 do
        as_new_device.(n)
        |> post(~p"/api/quizzes", %{"file" => QuizFixtures.package_upload()})
        |> json_response(201)
      end

      assert %{"code" => "too_many_submissions"} =
               as_new_device.(11)
               |> post(~p"/api/quizzes", %{"file" => QuizFixtures.package_upload()})
               |> json_response(429)

      # Still true once the rate limiter has swept: a day's count lasts the day.
      RateLimit.sweep()

      assert %{"code" => "too_many_submissions"} =
               as_new_device.(12)
               |> post(~p"/api/quizzes", %{"file" => QuizFixtures.package_upload()})
               |> json_response(429)
    end

    test "reports from one address stop counting after twenty a day", %{conn: conn} do
      # A reporter counts once per publisher key, and a key is whatever the caller
      # sends: without this one address could make one complaint look like many.
      quiz = QuizFixtures.published!()

      # The day's twenty, spent already (ten a minute would take two minutes to send).
      for _ <- 1..20, do: RateLimit.check(:reports_per_day, "127.0.0.1", 20, 86_400_000)

      assert conn
             |> put_req_header("x-owner-key", String.pad_trailing("reporter-", 44, "x"))
             |> post(~p"/api/quizzes/#{quiz.id}/report", %{"reason" => "spam"})
             |> response(204)

      # Answered like any other, and not kept.
      assert Repo.aggregate(Report, :count) == 0
    end

    test "and only so many bytes a day, however few packages" do
      day = 86_400_000
      assert RateLimit.check(:bytes_test, "9.9.9.9", 100, day, 60) == :ok
      assert RateLimit.check(:bytes_test, "9.9.9.9", 100, day, 60) == {:error, :rate_limited}
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
      # lock out the whole party. Production sets :proxy_hops for exactly this.
      Application.put_env(:fazoura, :proxy_hops, 1)
      on_exit(fn -> Application.delete_env(:fazoura, :proxy_hops) end)

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
      Application.put_env(:fazoura, :proxy_hops, 1)
      on_exit(fn -> Application.delete_env(:fazoura, :proxy_hops) end)

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

  describe "unreviewed uploads" do
    test "nothing can be put in the uploads volume without going through review",
         %{conn: conn} do
      # `POST /api/images` used to store a photo straight into public `/uploads`:
      # anonymous image hosting on this domain, and a photo an approved package could
      # point at without the reviewer ever seeing it.
      upload = %Plug.Upload{
        path: Plug.Upload.random_file!("fazoura-test"),
        filename: "x.png",
        content_type: "image/png"
      }

      File.write!(upload.path, QuizFixtures.png())

      assert conn
             |> put_req_header("x-owner-key", QuizFixtures.owner_key())
             |> post("/api/images", %{"file" => upload})
             |> json_response(404)
    end
  end

  describe "paging" do
    test "an offset past anything a database holds is not an error", %{conn: conn} do
      assert %{"quizzes" => []} =
               conn
               |> get(~p"/api/quizzes", %{"offset" => "99999999999999999999999"})
               |> json_response(200)
    end
  end

  describe "logs" do
    test "a room join writes neither its token nor the player's name to the log" do
      # Production logs at :info, where Phoenix writes a join's parameters.
      previous = Logger.level()
      Logger.configure(level: :info)
      on_exit(fn -> Logger.configure(level: previous) end)

      {:ok, code, host_token} = Rooms.create(QuizFixtures.pack())

      log =
        ExUnit.CaptureLog.capture_log([level: :info], fn ->
          {:ok, _, _} =
            join_room(code, %{"host_token" => host_token, "display_name" => "Zephyrine"})
        end)

      refute log =~ host_token
      refute log =~ "Zephyrine"
    end
  end

  describe "user content headers" do
    test "an uploaded photo cannot be sniffed as anything but its declared type", %{conn: conn} do
      # Only the first bytes are checked when storing, so the tail of a valid image can
      # contain anything; these headers are what stop a browser acting on it.
      # A structurally valid PNG whose ancillary chunk carries markup: the header check
      # cannot object to it, which is exactly why the response headers matter.
      {:ok, %{key: key}} =
        Fazoura.Quizzes.store_image(
          QuizFixtures.png_with_text("<script>alert(1)</script>"),
          QuizFixtures.owner_key()
        )

      served = get(conn, "/uploads/#{key}")

      assert served.status == 200
      assert ["nosniff"] = get_resp_header(served, "x-content-type-options")
      assert ["inline"] = get_resp_header(served, "content-disposition")
      assert ["sandbox; default-src 'none'"] = get_resp_header(served, "content-security-policy")
    end

    test "a private quiz's photo carries the same headers", %{conn: conn} do
      questions = [photo_question(1, 100)]
      assert conn |> post(~p"/api/rooms", inline_quiz(questions)) |> json_response(201)

      key =
        Images
        |> :ets.tab2list()
        |> Enum.find_value(fn
          {key, _type, _bytes} when is_binary(key) -> key
          _ -> nil
        end)

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
end

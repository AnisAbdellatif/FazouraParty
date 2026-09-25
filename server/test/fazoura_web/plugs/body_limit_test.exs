defmodule FazouraWeb.Plugs.BodyLimitTest do
  use FazouraWeb.ConnCase, async: true

  alias Fazoura.Quizzes.Archive
  alias FazouraWeb.Plugs.BodyLimit

  describe "matching a route" do
    @opts BodyLimit.init(
            default: 1_000,
            routes: %{
              ["api", "rooms"] => 50_000,
              ["api", "quizzes", :_] => 90_000,
              ["api", "quizzes", "special"] => 10
            }
          )

    defp declaring(path, bytes) do
      :post
      |> Plug.Test.conn("/" <> Enum.join(path, "/"))
      |> Plug.Conn.put_req_header("content-length", Integer.to_string(bytes))
      |> BodyLimit.call(@opts)
    end

    test "an exact route gets its own limit" do
      refute declaring(["api", "rooms"], 40_000).halted
      assert declaring(["api", "rooms"], 60_000).halted
    end

    test "a `:_` segment stands for one segment of any value" do
      refute declaring(["api", "quizzes", "e5f1"], 80_000).halted
      assert declaring(["api", "quizzes", "e5f1"], 95_000).halted
    end

    test "and for exactly one, so it cannot widen a longer path" do
      assert declaring(["api", "quizzes", "e5f1", "archive"], 2_000).halted
    end

    test "a body with no length at all is refused rather than read" do
      # Chunked: it used to count as empty here and be read up to the endpoint's
      # 32 MB on any route at all.
      conn =
        :post
        |> Plug.Test.conn("/api/tags")
        |> Plug.Conn.put_req_header("transfer-encoding", "chunked")
        |> BodyLimit.call(@opts)

      assert conn.halted
      assert conn.status == 411

      # A request with no body is not asked for one.
      refute (:get |> Plug.Test.conn("/api/tags") |> BodyLimit.call(@opts)).halted
    end

    test "an exact route wins over a pattern that also matches" do
      assert declaring(["api", "quizzes", "special"], 500).halted
    end

    test "anything unlisted gets the default" do
      refute declaring(["api", "tags"], 500).halted
      assert declaring(["api", "tags"], 2_000).halted
    end

    test "a body with no declared length is left to Plug.Parsers" do
      conn = :post |> Plug.Test.conn("/api/tags") |> BodyLimit.call(@opts)
      refute conn.halted
    end
  end

  describe "the routes this endpoint declares" do
    # A package is a whole quiz with its photos, and the reader accepts one up to
    # `Archive.max_bytes/0`. Publishing used to fall to the 1 MB default, which
    # turned away any quiz with more than a photo or two in it.
    @package_size 4_000_000

    setup do
      {:ok, key: Fazoura.QuizFixtures.owner_key()}
    end

    defp submitting(conn, method, path, key) do
      conn
      |> put_req_header("x-owner-key", key)
      |> put_req_header("content-length", Integer.to_string(@package_size))
      |> then(&Phoenix.ConnTest.dispatch(&1, @endpoint, method, path, %{}))
    end

    test "publishing takes a package far larger than an ordinary body", %{
      conn: conn,
      key: key
    } do
      assert @package_size > 1_000_000
      assert @package_size < Archive.max_bytes()

      refute submitting(conn, :post, "/api/quizzes", key).status == 413
    end

    test "so does replacing a published quiz", %{conn: conn, key: key} do
      quiz = Fazoura.QuizFixtures.published!()

      refute submitting(conn, :put, "/api/quizzes/#{quiz.id}", key).status == 413
    end

    test "creating a room does too — it carries a quiz inline", %{conn: conn, key: key} do
      refute submitting(conn, :post, "/api/rooms", key).status == 413
    end

    test "an ordinary route does not", %{conn: conn, key: key} do
      assert submitting(conn, :get, "/api/tags", key).status == 413
    end
  end
end

defmodule FazouraWeb.Plugs.WebAppTest do
  use FazouraWeb.ConnCase, async: false

  alias FazouraWeb.Plugs.WebApp

  @index "<!DOCTYPE html><html><body>fazoura</body></html>"

  setup do
    dir = Path.join(System.tmp_dir!(), "fazoura_web_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "canvaskit"))
    File.write!(Path.join(dir, "index.html"), @index)
    File.write!(Path.join(dir, "main.dart.js"), "console.log('app')")
    File.write!(Path.join(dir, "favicon.png"), "png")
    File.write!(Path.join(dir, "apple-touch-icon.png"), "png")
    File.mkdir_p!(Path.join(dir, "icons"))
    File.write!(Path.join(dir, "icons/Icon-512.png"), "png")
    File.write!(Path.join(dir, "manifest.json"), ~s({"name": "Fazoura Party"}))
    File.write!(Path.join(dir, "flutter_service_worker.js"), "// sw")
    File.write!(Path.join(dir, "canvaskit/canvaskit.wasm"), "wasm")
    File.write!(Path.join(dir, "main.dart.js_1.part.js"), "// the quiz editor")
    File.write!(Path.join(dir, "main.dart.js.br"), "brotli bytes")

    previous = Application.get_env(:fazoura, :web_dir)
    Application.put_env(:fazoura, :web_dir, dir)

    on_exit(fn ->
      Application.put_env(:fazoura, :web_dir, previous)
      File.rm_rf!(dir)
    end)

    %{dir: dir}
  end

  test "hands out the precompressed copy when the client takes brotli", %{conn: conn} do
    # The build compresses once; without this the server would recompress a few
    # megabytes on every cold visit.
    conn = conn |> put_req_header("accept-encoding", "br") |> get("/main.dart.js")

    assert response(conn, 200) == "brotli bytes"
    assert get_resp_header(conn, "content-encoding") == ["br"]
    assert get_resp_header(conn, "vary") == ["Accept-Encoding"]
  end

  test "falls back to the plain file when it doesn't", %{conn: conn} do
    # Caddy compresses this one on the way out, as it did before.
    conn = conn |> put_req_header("accept-encoding", "gzip") |> get("/main.dart.js")

    assert response(conn, 200) == "console.log('app')"
    assert get_resp_header(conn, "content-encoding") == []
  end

  test "serves the deferred chunks the app splits out", %{conn: conn} do
    # `:only` matches a whole first segment and these carry a number, so they
    # need the prefix list. A 404 here takes the screen that was split out and
    # the service worker with it: one failure inside `cache.addAll` rejects the
    # whole install, and then nothing works offline either.
    conn = get(conn, "/main.dart.js_1.part.js")

    assert response(conn, 200) == "// the quiz editor"
    assert get_resp_header(conn, "cache-control") == ["public, max-age=0, must-revalidate"]
  end

  test "still refuses what the build never emits", %{conn: conn, dir: dir} do
    File.write!(Path.join(dir, "secrets.env"), "nope")
    File.write!(Path.join(dir, "notes.txt"), "nope")

    assert get(conn, "/secrets.env").status == 404
    assert get(conn, "/notes.txt").status == 404
    assert get(conn, "/../mix.exs").status == 404
  end

  test "serves the app shell at the root", %{conn: conn} do
    conn = get(conn, "/")

    assert response(conn, 200) == @index
    assert response_content_type(conn, :html) =~ "text/html"
    assert get_resp_header(conn, "cache-control") == ["public, max-age=0, must-revalidate"]
  end

  test "serves the bundle with revalidation, never a long-lived cache", %{conn: conn} do
    paths = [
      "/main.dart.js",
      "/flutter_service_worker.js",
      "/canvaskit/canvaskit.wasm",
      # Everything the installed app asks for, including the icons a browser
      # fetches by convention rather than from the page.
      "/manifest.json",
      "/favicon.png",
      "/apple-touch-icon.png",
      "/icons/Icon-512.png"
    ]

    for path <- paths do
      conn = get(build_conn(), path)
      assert conn.status == 200
      assert get_resp_header(conn, "cache-control") == ["public, max-age=0, must-revalidate"]
      assert [_etag] = get_resp_header(conn, "etag")
    end

    # A second request with the ETag is a cheap 304.
    first = get(build_conn(), "/main.dart.js")
    [etag] = get_resp_header(first, "etag")

    second = build_conn() |> put_req_header("if-none-match", etag) |> get("/main.dart.js")
    assert second.status == 304

    assert conn.method == "GET"
  end

  test "serves the app unframeable, with sniffing off", %{conn: conn} do
    # The live host screen must never be embeddable, or a page could overlay it and
    # steal a tap (clickjacking). Both the shell and a static asset carry the headers.
    for path <- ["/", "/main.dart.js"] do
      conn = get(build_conn(), path)
      assert conn.status == 200
      assert get_resp_header(conn, "x-frame-options") == ["DENY"]
      assert get_resp_header(conn, "content-security-policy") == ["frame-ancestors 'none'"]
      assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
      assert get_resp_header(conn, "referrer-policy") == ["strict-origin-when-cross-origin"]
    end

    assert conn.method == "GET"
  end

  test "leaves the API, uploads and unknown paths alone", %{conn: conn} do
    Fazoura.QuizFixtures.builtin!("general-knowledge")

    assert %{"quizzes" => quizzes} = conn |> get(~p"/api/quizzes") |> json_response(200)
    assert quizzes != []
    assert build_conn() |> get("/nope.txt") |> response(404)
  end

  test "does nothing when no web app is configured" do
    Application.put_env(:fazoura, :web_dir, nil)

    assert build_conn() |> get("/") |> response(404)
    assert WebApp.dir() == nil
  end

  test "ignores a configured directory that isn't there" do
    Application.put_env(:fazoura, :web_dir, Path.join(System.tmp_dir!(), "not-built"))

    assert WebApp.dir() == nil
    assert build_conn() |> get("/") |> response(404)
  end
end

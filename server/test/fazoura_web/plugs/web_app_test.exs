defmodule FazouraWeb.Plugs.WebAppTest do
  use FazouraWeb.ConnCase, async: false

  @index "<!DOCTYPE html><html><body>fazoura</body></html>"

  setup do
    dir = Path.join(System.tmp_dir!(), "fazoura_web_#{System.unique_integer([:positive])}")
    File.mkdir_p!(Path.join(dir, "canvaskit"))
    File.write!(Path.join(dir, "index.html"), @index)
    File.write!(Path.join(dir, "main.dart.js"), "console.log('app')")
    File.write!(Path.join(dir, "flutter_service_worker.js"), "// sw")
    File.write!(Path.join(dir, "canvaskit/canvaskit.wasm"), "wasm")

    previous = Application.get_env(:fazoura, :web_dir)
    Application.put_env(:fazoura, :web_dir, dir)

    on_exit(fn ->
      Application.put_env(:fazoura, :web_dir, previous)
      File.rm_rf!(dir)
    end)

    %{dir: dir}
  end

  test "serves the app shell at the root", %{conn: conn} do
    conn = get(conn, "/")

    assert response(conn, 200) == @index
    assert response_content_type(conn, :html) =~ "text/html"
    assert get_resp_header(conn, "cache-control") == ["public, max-age=0, must-revalidate"]
  end

  test "serves the bundle with revalidation, never a long-lived cache", %{conn: conn} do
    for path <- ["/main.dart.js", "/flutter_service_worker.js", "/canvaskit/canvaskit.wasm"] do
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

  test "leaves the API, uploads and unknown paths alone", %{conn: conn} do
    Fazoura.Quizzes.sync_builtin!()

    assert %{"quizzes" => [_]} = conn |> get(~p"/api/quizzes") |> json_response(200)
    assert build_conn() |> get("/nope.txt") |> response(404)
  end

  test "does nothing when no web app is configured" do
    Application.put_env(:fazoura, :web_dir, nil)

    assert build_conn() |> get("/") |> response(404)
    assert FazouraWeb.Plugs.WebApp.dir() == nil
  end

  test "ignores a configured directory that isn't there" do
    Application.put_env(:fazoura, :web_dir, Path.join(System.tmp_dir!(), "not-built"))

    assert FazouraWeb.Plugs.WebApp.dir() == nil
    assert build_conn() |> get("/") |> response(404)
  end
end

defmodule FazouraWeb.ImageControllerTest do
  use FazouraWeb.ConnCase, async: false

  alias Fazoura.QuizFixtures

  # A real 1x1 PNG: uploads are validated structurally, not just by magic bytes.
  @png QuizFixtures.png()

  defp upload(binary, filename) do
    path = Path.join(System.tmp_dir!(), "fazoura-upload-#{System.unique_integer([:positive])}")
    File.write!(path, binary)
    %Plug.Upload{path: path, filename: filename, content_type: "application/octet-stream"}
  end

  test "uploads an image and serves it at its url", %{conn: conn} do
    response =
      conn
      |> put_req_header("x-owner-key", QuizFixtures.owner_key())
      |> post(~p"/api/images", %{file: upload(@png, "still.png")})
      |> json_response(201)

    assert %{"key" => key, "url" => url} = response
    assert String.ends_with?(key, ".png")
    assert String.ends_with?(url, "/uploads/" <> key)

    served = get(build_conn(), "/uploads/" <> key)
    assert response(served, 200) == @png
  end

  test "rejects missing keys, unsupported files and missing parts", %{conn: conn} do
    assert %{"code" => "owner_key_required"} =
             conn |> post(~p"/api/images", %{file: upload(@png, "a.png")}) |> json_response(401)

    authed = put_req_header(conn, "x-owner-key", QuizFixtures.owner_key())

    assert %{"code" => "unsupported_image"} =
             authed
             |> post(~p"/api/images", %{file: upload("GIF89a…", "fake.png")})
             |> json_response(415)

    assert %{"code" => "missing_file"} =
             authed |> post(~p"/api/images", %{}) |> json_response(422)
  end
end

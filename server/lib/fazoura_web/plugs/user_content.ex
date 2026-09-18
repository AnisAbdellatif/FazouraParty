defmodule FazouraWeb.Plugs.UserContent do
  @moduledoc """
  Response headers for bytes a user uploaded, served from our own origin.

  Photos are validated by magic bytes before they are stored (`Fazoura.Uploads.detect/1`)
  and their filenames are server-generated, so the declared type is honest. What these
  headers guard is the rest of the file: only the first few bytes are checked, so a valid
  JPEG can carry anything after them, and this origin also serves the app.

  - `X-Content-Type-Options: nosniff` — the browser must believe `image/webp` rather than
    sniffing markup out of the tail of the file.
  - `Content-Disposition: inline` — never offer it as a download, and never let a
    filename influence how it is saved.
  - `Content-Security-Policy: sandbox` — if it is ever navigated to directly, it gets an
    opaque origin, so any script inside cannot touch this one's cookies or storage.
  """

  import Plug.Conn

  @doc "Registers the headers, applied when the response is sent."
  @spec protect(Plug.Conn.t()) :: Plug.Conn.t()
  def protect(conn) do
    register_before_send(conn, fn conn ->
      conn
      |> put_resp_header("x-content-type-options", "nosniff")
      |> put_resp_header("content-disposition", "inline")
      |> put_resp_header("content-security-policy", "sandbox; default-src 'none'")
    end)
  end
end

defmodule FazouraWeb.Plugs.Uploads do
  @moduledoc """
  Serves uploaded question photos from the configured uploads directory at
  `/uploads/<key>`. The directory is read at request time so it can differ per
  environment (a mounted volume in production).
  """

  @behaviour Plug

  alias FazouraWeb.Plugs.UserContent

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{path_info: ["uploads" | _]} = conn, _opts) do
    static =
      Plug.Static.init(
        at: "/uploads",
        from: Fazoura.Uploads.dir(),
        gzip: false,
        # A day, not a year and `immutable`: a photo taken down after a report has to
        # stop being served from caches too, and a year meant it could not be. A key
        # never changes its bytes, so the ETag still makes a revalidation cheap.
        cache_control_for_etags: "public, max-age=86400"
      )

    conn
    |> UserContent.protect()
    |> Plug.Static.call(static)
  end

  def call(conn, _opts), do: conn
end

defmodule FazouraWeb.Plugs.Uploads do
  @moduledoc """
  Serves uploaded question photos from the configured uploads directory at
  `/uploads/<key>`. The directory is read at request time so it can differ per
  environment (a mounted volume in production).
  """

  @behaviour Plug

  @impl true
  def init(opts), do: opts

  @impl true
  def call(%Plug.Conn{path_info: ["uploads" | _]} = conn, _opts) do
    static =
      Plug.Static.init(
        at: "/uploads",
        from: Fazoura.Uploads.dir(),
        gzip: false,
        cache_control_for_etags: "public, max-age=31536000, immutable"
      )

    Plug.Static.call(conn, static)
  end

  def call(conn, _opts), do: conn
end

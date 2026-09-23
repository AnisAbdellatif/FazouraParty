defmodule FazouraWeb.PageController do
  @moduledoc """
  Static pages that have to live at a stable public URL — today only the privacy
  policy, which app stores link to.

  The page is read at compile time, so a release carries it inside the beam and there
  is no path to get wrong at runtime. It is served like the web app: revalidated on
  every visit, because a policy is exactly the page that must never be served stale.
  """
  use FazouraWeb, :controller

  @privacy Path.expand("../../../priv/pages/privacy.html", __DIR__)
  @external_resource @privacy
  @privacy_html File.read!(@privacy)

  def privacy(conn, _params) do
    conn
    |> put_resp_header("cache-control", "public, max-age=0, must-revalidate")
    |> put_resp_content_type("text/html")
    |> send_resp(200, @privacy_html)
  end
end

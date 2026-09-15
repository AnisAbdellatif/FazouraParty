defmodule FazouraWeb.Admin.Auth do
  @moduledoc """
  `on_mount` hook for the admin LiveViews.

  The websocket carries no Basic auth header, so the HTTP request that served the page
  leaves a flag in the session (`FazouraWeb.Plugs.AdminAuth`) and the LiveView checks it.
  """

  import Phoenix.LiveView

  alias FazouraWeb.Plugs.AdminAuth

  def on_mount(:ensure_admin, _params, session, socket) do
    if AdminAuth.admin_session?(session) do
      {:cont, socket}
    else
      {:halt, redirect(socket, to: "/admin")}
    end
  end
end

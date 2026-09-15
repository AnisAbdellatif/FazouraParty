defmodule FazouraWeb.HealthController do
  use FazouraWeb, :controller

  def show(conn, _params), do: json(conn, %{status: "ok"})
end

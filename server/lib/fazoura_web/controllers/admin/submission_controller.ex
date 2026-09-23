defmodule FazouraWeb.Admin.SubmissionController do
  @moduledoc """
  Photos inside a submission, for the review screen (ADMIN.md §3.2).

  They are not in the uploads volume and must not be: nothing unreviewed is
  served from disk. So each one is read out of the package on request, behind
  the dashboard's own credentials, and never cached.
  """

  use FazouraWeb, :controller

  alias Fazoura.Admin

  @spec photo(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def photo(conn, %{"id" => id, "path" => path}) do
    with {:ok, submission} <- Admin.fetch_submission(id),
         {:ok, %{photos: photos}} <- Admin.submission_contents(submission),
         {:ok, bytes} <- Map.fetch(photos, path) do
      conn
      # Unreviewed bytes somebody uploaded: never sniffed, never framed, never
      # kept — the same headers a published photo gets, for the same reason.
      |> put_resp_content_type("application/octet-stream")
      |> put_resp_header("x-content-type-options", "nosniff")
      |> put_resp_header("content-security-policy", "default-src 'none'; sandbox")
      |> put_resp_header("cache-control", "no-store")
      |> send_resp(200, bytes)
    else
      _ -> conn |> put_resp_content_type("text/plain") |> send_resp(404, "No such photo.")
    end
  end
end

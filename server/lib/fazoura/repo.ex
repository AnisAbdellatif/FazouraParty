defmodule Fazoura.Repo do
  # SQLite locally (dev/test), Postgres in production. Migrations and queries must
  # stay portable across both (see AGENTS.md).
  use Ecto.Repo,
    otp_app: :fazoura,
    adapter: Application.compile_env(:fazoura, :repo_adapter, Ecto.Adapters.Postgres)
end

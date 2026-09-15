defmodule Fazoura.Repo do
  use Ecto.Repo,
    otp_app: :fazoura,
    adapter: Ecto.Adapters.Postgres
end

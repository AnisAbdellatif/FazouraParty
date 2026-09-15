# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :fazoura,
  ecto_repos: [Fazoura.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true],
  start_repo: true,
  # Postgres on the server, SQLite on developer machines.
  repo_adapter:
    if(config_env() == :prod, do: Ecto.Adapters.Postgres, else: Ecto.Adapters.SQLite3),
  # Uploaded question photos (served at /uploads). Overridden in runtime.exs for prod.
  uploads_dir: Path.expand("../priv/uploads", __DIR__),
  cors_origins: []

# Configure the endpoint
config :fazoura, FazouraWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: FazouraWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Fazoura.PubSub,
  live_view: [signing_salt: "hYu2QOKT"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

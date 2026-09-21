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
  # Drop `.fazoura` packages here and they are seeded on the next setup, named by their
  # filename (QUIZ_FORMAT.md §6). Overridden in runtime.exs for prod (PACKAGES_DIR).
  packages_dir: Path.expand("../priv/packages", __DIR__),
  # Collects photos no quiz references any more (unpublished, replaced, abandoned).
  image_sweeper: [enabled: true, interval_ms: :timer.hours(1), grace_seconds: 86_400],
  # How long shutdown waits for "room closed" to reach live clients.
  drain_ms: 500,
  cors_origins: [],
  # /admin is disabled unless both are set (runtime.exs reads ADMIN_USERNAME/ADMIN_PASSWORD).
  admin: [username: nil, password: nil],
  # Built Flutter web app to serve at "/"; nil serves the API only (runtime.exs: WEB_DIR).
  web_dir: nil

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

# A `.fazoura` package is a ZIP (QUIZ_FORMAT.md §5.3b). The admin dashboard's upload
# accepts files by extension, and LiveView will only accept one MIME knows about.
config :mime, :types, %{"application/zip" => ["zip", "fazoura"]}

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

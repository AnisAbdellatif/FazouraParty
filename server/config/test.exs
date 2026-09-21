import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :fazoura, Fazoura.Repo,
  database: Path.expand("../fazoura_test#{System.get_env("MIX_TEST_PARTITION")}.db", __DIR__),
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: 5

config :fazoura, uploads_dir: Path.expand("../tmp/test_uploads", __DIR__)

# Nothing to seed unless a test says so: the packages that ship in priv would otherwise
# turn up in every test that counts quizzes.
config :fazoura,
  packages_dir: Path.expand("../tmp/test_packages", __DIR__),
  packages_drop_dir: nil

# Sweeping and draining are driven directly by their tests, never on a timer.
config :fazoura, image_sweeper: [enabled: false]
config :fazoura, drain_ms: 0

# Off by default: counters are per-IP and every test shares 127.0.0.1, so a suite that
# grows would start tripping the limit rather than testing what it meant to. The
# rate-limit tests turn it on for themselves.
config :fazoura, rate_limit_enabled: false

config :fazoura, admin: [username: "admin", password: "test-admin-password"]

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :fazoura, FazouraWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "k5SUwu1ij5bJE6SE8bvDYEvD/QzbkH+KkX3vDO4VlS7udhu4/OuehxD2RmMZ8zeH",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

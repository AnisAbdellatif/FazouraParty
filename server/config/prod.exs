import Config

# The admin session cookie is HTTPS-only here; in dev the dashboard is plain http.
config :fazoura, secure_cookies: true

# Force using SSL in production. The local Docker image opts out at build time because
# it is reached directly over plain HTTP by Android emulators and LAN devices.
# Note `:force_ssl` is required to be set at compile-time.
if System.get_env("FORCE_SSL", "true") == "true" do
  config :fazoura, FazouraWeb.Endpoint,
    force_ssl: [
      rewrite_on: [:x_forwarded_proto],
      exclude: [
        # paths: ["/health"],
        hosts: ["localhost", "127.0.0.1"]
      ]
    ]
end

# Do not print debug messages in production
config :logger, level: :info

# Runtime production configuration, including reading
# of environment variables, is done on config/runtime.exs.

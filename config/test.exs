import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :volvox_server, VolvoxServerWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "dB69WXttV5zeQxdPgvSpW7K0+1D55JLElI8U4lIv6IQMsCa73802O4iMeYm+CmDB",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

config :volvox_server,
  work_dir: Path.expand("../tmp/test/work", __DIR__),
  local_objects: Path.expand("../tmp/test/runs", __DIR__),
  objects: :local,
  req_options: [plug: {Req.Test, VolvoxServer.Fetch}]

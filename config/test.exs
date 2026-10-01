import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :moss, MossWeb.Endpoint,
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

config :moss,
  work_dir: Path.expand("../tmp/test/work", __DIR__),
  local_objects: Path.expand("../tmp/test/runs", __DIR__),
  objects: :local,
  host_dir: Path.expand("../tmp/test/host", __DIR__),
  page_tokens: %{"test-page-token" => "tester"},
  req_options: [plug: {Req.Test, Moss.Fetch}],
  computer_req_options: [plug: {Req.Test, Moss.Computer.Net}],
  # the post's batches run when a test says (Mail.screen_now), read by a stand-in for Jev
  mail_window: 3_600_000,
  mail_jev: Moss.TestJev

# a run's instruction budget, small enough that the test that exhausts it is quick
config :moss, script_instructions: 20_000_000

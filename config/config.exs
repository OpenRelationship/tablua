# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :moss,
  generators: [timestamp_type: :utc_datetime]

# Moss is attached to the Arock repository at submodules/moss; Arock Core's Lua
# modules load from that repository's library/ and submodules/alog (AROCK_ROOT
# names another checkout). A computer's SQLite disk lives under work_dir while it is
# awake; asleep, it is kept by Arock's service with this node's own token
# (MOSS_NODE_TOKEN or the keychain item moss-node-token), or under local_objects
# when the node has none (objects: :auto picks; :local or :service forces one).
arock = System.get_env("AROCK_ROOT") || Path.expand("../../..", __DIR__)

config :moss,
  core: arock,
  work_dir: Path.expand("../priv/work", __DIR__),
  local_objects: Path.expand("../priv/runs", __DIR__),
  objects: :auto,
  # an awake computer's file streamed by Litestream and shipped as its log (Moss.Litestream): :litestream, :whole
  # (its whole file at sleep), or :auto (Litestream when its binary is found)
  replication: :auto,
  # how often an awake computer's log is cut into a segment and shipped (owner's approval, 2026-10-01): each
  # segment is one R2 write, so 10 s costs a tenth of 1 s (about 5 cents a month for a computer working an hour a
  # day); a sleep still syncs and ships everything first, so only a crash of the node loses up to 10 s
  litestream_sync: "10s",
  ship_ms: 10_000

# The node's own books (the post) live under host_dir.
config :moss,
  host_dir: Path.expand("../priv/host", __DIR__)

# Configure the endpoint
config :moss, MossWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: MossWeb.ErrorHTML],
    layout: false
  ],
  pubsub_server: Moss.PubSub,
  live_view: [signing_salt: "r36zSyke"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  moss: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  moss: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

# SQLite from source, with mix.exs's flags (an awake computer's connection allocates only what it uses), on the
# system's malloc: through the BEAM's allocator, which a dirty scheduler reaches through one shared instance, every
# computer's SQLite waited on the others' allocations (a log's event is many of them)
config :exqlite, force_build: true, disable_erlang_allocator: true

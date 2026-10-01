# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :volvox_server,
  generators: [timestamp_type: :utc_datetime]

# Volvox is the submodule; its Lua modules load from its library/. The Colm
# suite modules are what `just build-script suite` writes in the Volvox repo.
# A run's SQLite file lives under work_dir while the run is awake; asleep, it
# is an object runs/<id>.sqlite in R2, or under local_objects when wrangler is
# not logged in (objects: :auto picks; :local or :r2 forces one).
config :volvox_server,
  volvox: Path.expand("../submodules/volvox", __DIR__),
  suite: Path.expand("~/volvox/.cache/volvox/suite"),
  programs: Path.expand("~/volvox/.cache/volvox/computer"),
  work_dir: Path.expand("../priv/work", __DIR__),
  local_objects: Path.expand("../priv/runs", __DIR__),
  objects: :auto

# The node's own books (the schedule, the Mac's queue) live under host_dir; the
# schedule is looked at every tick_ms. Agents a task can name: name => Lua file.
config :volvox_server,
  host_dir: Path.expand("../priv/host", __DIR__),
  tick_ms: 5_000,
  agents: %{}

# Configure the endpoint
config :volvox_server, VolvoxServerWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: VolvoxServerWeb.ErrorHTML],
    layout: false
  ],
  pubsub_server: VolvoxServer.PubSub,
  live_view: [signing_salt: "r36zSyke"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  volvox_server: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  volvox_server: [
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

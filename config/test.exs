import Config

config :logger, level: :warning

config :moss,
  work_dir: Path.expand("../tmp/test/work", __DIR__),
  req_options: [plug: {Req.Test, Moss.Fetch}],
  computer_req_options: [plug: {Req.Test, Moss.Computer.Net}],
  script_instructions: 20_000_000

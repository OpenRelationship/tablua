import Config

# Arock Core's Lua (library/, arock-log, arock-mail, Shroomi, connectory's port) from the Arock checkout this moss is
# attached to (submodules/moss), or AROCK_ROOT. A host (arock-server) sets these for its node in its own config.
arock = System.get_env("AROCK_ROOT") || Path.expand("../../..", __DIR__)

config :moss,
  core: arock,
  work_dir: Path.expand("../priv/work", __DIR__),
  # A computer that never sleeps is snapshotted where it is every snapshot_ms, by its host (Moss.Host.cut/1); the
  # host's config says why 4 hours.
  snapshot_ms: 4 * 3_600_000

# moss-browser's look (Arock feature look): its v0.1.1 module, pinned by SHA-384 and fetched by mix moss.look
config :moss, :look,
  release: "v0.1.1",
  sha384:
    "867622badaf55464ed5d66e0583455145a443ab80fdce263b4df644a63100732e256b1bf7edae34f557f8ad6af7e8c56",
  path: Path.expand("../priv/look.wasm", __DIR__)

config :logger, :default_formatter, format: "$time $metadata[$level] $message\n"

import_config "#{config_env()}.exs"

# SQLite built from source with the flags mix.exs sets (EXQLITE_SYSTEM_CFLAGS), and its own allocator
config :exqlite, force_build: true, disable_erlang_allocator: true

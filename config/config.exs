import Config

# Arock Core's Lua (library/, arock-log, arock-mail, Shroomi, connectory's port) from the Arock checkout this moss is
# attached to (submodules/vmoss), or AROCK_ROOT. A host (arock-server) sets these for its node in its own config.
arock = System.get_env("AROCK_ROOT") || Path.expand("../../..", __DIR__)

config :moss,
  core: arock,
  work_dir: Path.expand("../priv/work", __DIR__),
  # A computer that never sleeps is snapshotted where it is every snapshot_ms, by its host (Moss.Host.cut/1); the
  # host's config says why 4 hours.
  snapshot_ms: 4 * 3_600_000

# The look (Arock feature look): the module VMOSS's CI built from browser/look and released, pinned by SHA-384 and
# fetched by mix moss.look. A new release is a new version and hash here, in the change that adopts it.
config :moss, :look,
  repo: "OpenRelationship/vmoss",
  release: "v0.2.0",
  sha384:
    "0deb35705424acc1b0e4f6e325978cef5b8de84b253704090fe70fededf12aae61f2344026fdd94264e5012a7b86b7b7",
  path: Path.expand("../priv/look.wasm", __DIR__)

config :logger, :default_formatter, format: "$time $metadata[$level] $message\n"

import_config "#{config_env()}.exs"

# SQLite built from source with the flags mix.exs sets (EXQLITE_SYSTEM_CFLAGS), and its own allocator
config :exqlite, force_build: true, disable_erlang_allocator: true

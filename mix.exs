# SQLite is built from source (config :exqlite, force_build: true) with two allocations a computer's connection
# never needs: the lookaside pool (100 slots of 1,200 bytes, made per connection) and the 20 pages the page cache
# makes up front. Off, an awake computer is about 54 KB instead of 165 KB (bench/computers.exs). Memory statistics are
# off too: SQLite counts every allocation under one lock, and a computer's log makes many of them.
System.put_env(
  "EXQLITE_SYSTEM_CFLAGS",
  "-DSQLITE_DEFAULT_LOOKASIDE=0,0 -DSQLITE_DEFAULT_PCACHE_INITSZ=0 -DSQLITE_DEFAULT_MEMSTATUS=0"
)

defmodule Moss.MixProject do
  use Mix.Project

  # MOSS, the agent's own computer (Arock PROJECT.md §14): a library a host runs (Moss.Host), arock-server on a node.
  def project do
    [
      app: :moss,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      mod: {Moss.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:phoenix_pubsub, "~> 2.1"},
      # lexbor, in C: only for tests (the cleaner's tests use it as a second, browser-grade parser). No page an
      # agent writes or fetches reaches it (Arock PROJECT.md §14.7).
      {:lazy_html, ">= 0.1.0", only: :test},
      {:jason, "~> 1.2"},
      # moss-lua (lua/): our own tv-labs lua, maintained by us (owner, 2026-10-01; renamed from luos and
      # luex, 2026-10-02)
      {:lua, path: "lua"},
      # moss-browser (browser/): the browser engine, its own repository (owner, 2026-10-02)
      {:moss_browser, path: "browser"},
      {:exqlite, "~> 0.41"},
      {:req, "~> 0.5"},
      # a form or query string encoded as Phoenix does (Moss.Computer.Script.Http)
      {:plug, "~> 1.16"}
    ]
  end
end

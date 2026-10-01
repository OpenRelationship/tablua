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

  def project do
    [
      app: :moss,
      version: "0.1.0",
      elixir: "~> 1.15",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      compilers: [:phoenix_live_view] ++ Mix.compilers(),
      listeners: [Phoenix.CodeReloader]
    ]
  end

  # Configuration for the OTP application.
  #
  # Type `mix help compile.app` for more information.
  def application do
    [
      mod: {Moss.Application, []},
      extra_applications: [:logger, :runtime_tools]
    ]
  end

  def cli do
    [
      preferred_envs: [precommit: :test]
    ]
  end

  # Specifies which paths to compile per environment.
  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  # Specifies your project dependencies.
  #
  # Type `mix help deps` for examples and options.
  defp deps do
    [
      {:phoenix, "~> 1.8.4"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_reload, "~> 1.2", only: :dev},
      {:phoenix_live_view, "~> 1.1.0"},
      {:lazy_html, ">= 0.1.0"},
      {:esbuild, "~> 0.10", runtime: Mix.env() == :dev},
      {:tailwind, "~> 0.3", runtime: Mix.env() == :dev},
      {:heroicons,
       github: "tailwindlabs/heroicons",
       tag: "v2.2.0",
       sparse: "optimized",
       app: false,
       compile: false,
       depth: 1},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:bandit, "~> 1.5"},
      # luos (Arock's submodules/luos): our own tv-labs lua, maintained by us (owner, 2026-10-01), read from the
      # Arock checkout Moss is attached to, as Arock Core and Shroomi are (AROCK_ROOT names another)
      {:lua, path: Path.join(System.get_env("AROCK_ROOT") || Path.expand("../..", __DIR__), "submodules/luos")},
      {:exqlite, "~> 0.41"},
      {:req, "~> 0.5"}
    ]
  end

  # Aliases are shortcuts or tasks specific to the current project.
  # For example, to install project dependencies and perform other setup tasks, run:
  #
  #     $ mix setup
  #
  # See the documentation for `Mix` for more info on aliases.
  defp aliases do
    [
      setup: ["deps.get", "assets.setup", "assets.build"],
      "assets.setup": ["tailwind.install --if-missing", "esbuild.install --if-missing"],
      "assets.build": ["compile", "tailwind moss", "esbuild moss"],
      "assets.deploy": [
        "tailwind moss --minify",
        "esbuild moss --minify",
        "phx.digest"
      ],
      precommit: ["compile --warnings-as-errors", "deps.unlock --unused", "format", "test"]
    ]
  end
end

defmodule Moss.Lua.Sources do
  @moduledoc """
  Arock Core's Lua modules as `name => source`, read from the Arock repository:
  its `library/` (`library/ports/jev.lua` is `ports.jev`) and arock-log, the log, at
  `library/arock-log` (`init.lua` is `arock-log`, `robot.lua` is `arock-log.robot`),
  Shroomi at `submodules/shroomi` (`shroomi`, `shroomi.css`, ...), and
  arock-mail, the post's checks and Jev's reading (PROJECT.md §18), at
  `library/arock-mail` (`checks.lua` is `arock-mail.checks`), and connectory's
  port at `submodules/connectory/lua` (`connectory.lua.port_http`, which
  `ports.connect` requires). Unit
  tests (`*_test.lua`) and LuaJIT host code (any file that requires `ffi`, such
  as `arock-log.ffi` and `ports.curl`) are left out; this host supplies those ports
  itself.
  """

  def core, do: Application.fetch_env!(:moss, :core)

  def library, do: Path.join(core(), "library")

  @doc "Where core modules live, each with the prefix its module names take."
  def roots,
    do: [
      {library(), ""},
      {Path.join(core(), "library/arock-log"), "arock-log"},
      {Path.join(core(), "submodules/shroomi"), "shroomi"},
      {Path.join(core(), "library/arock-mail"), "arock-mail"},
      {Path.join(core(), "submodules/connectory/lua"), "connectory.lua"}
    ]

  @doc "Every core module, by module name."
  def all do
    for {root, prefix} <- roots(),
        file <- Path.wildcard(Path.join(root, "**/*.lua")),
        !String.ends_with?(file, "_test.lua"),
        src = File.read!(file),
        !(src =~ ~r/require\(\s*"ffi"\s*\)/),
        into: %{},
        do: {module_name(root, file, prefix), src}
  end

  @doc "The module name a file under `root` is required by, after `prefix`."
  def module_name(root, path, prefix \\ "") do
    name =
      path
      |> Path.relative_to(root)
      |> Path.rootname()
      |> String.replace_suffix("/init", "")
      |> String.replace("/", ".")

    cond do
      prefix == "" -> name
      name == "init" -> prefix
      true -> prefix <> "." <> name
    end
  end

  @doc """
  This host's own modules, run on the host and never on a computer: the computer's agent world in
  priv/lua/world (`world.lua` is `moss.world`, `run.lua` is `moss.world.run`).
  """
  def own do
    root = Path.join(:code.priv_dir(:moss), "lua/world")

    for file <- Path.wildcard(Path.join(root, "*.lua")), into: %{} do
      name = Path.rootname(Path.basename(file))
      {if(name == "world", do: "moss.world", else: "moss.world." <> name), File.read!(file)}
    end
  end

  @doc "A Lua file of this host, from priv/lua."
  def priv(name), do: File.read!(Path.join(:code.priv_dir(:moss), "lua/" <> name))
end

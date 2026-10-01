defmodule Moss.Lua.Sources do
  @moduledoc """
  Arock Core's Lua modules as `name => source`, read from the Arock repository:
  its `library/` (`library/ports/jev.lua` is `ports.jev`) and alog, the log, at
  `submodules/alog` (`init.lua` is `alog`, `robot.lua` is `alog.robot`). Unit
  tests (`*_test.lua`) and LuaJIT host code (any file that requires `ffi`, such
  as `alog.ffi` and `ports.curl`) are left out; this host supplies those ports
  itself.
  """

  def core, do: Application.fetch_env!(:moss, :core)

  def library, do: Path.join(core(), "library")

  @doc "Where core modules live, each with the prefix its module names take."
  def roots, do: [{library(), ""}, {Path.join(core(), "submodules/alog"), "alog"}]

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

  @doc "A Lua file of this host, from priv/lua."
  def priv(name), do: File.read!(Path.join(:code.priv_dir(:moss), "lua/" <> name))
end

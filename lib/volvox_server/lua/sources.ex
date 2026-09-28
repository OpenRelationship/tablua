defmodule VolvoxServer.Lua.Sources do
  @moduledoc """
  Volvox's Lua modules as `name => source`, read from the submodule's
  `library/`: `library/store/init.lua` is `store`, `library/plan/machines/code.lua`
  is `plan.machines.code`. Unit tests (`*_test.lua`) and LuaJIT host code (any
  file that requires `ffi`, such as `store.ffi` and `ports.curl`) are left out;
  this host supplies those ports itself.
  """

  def volvox, do: Application.fetch_env!(:volvox_server, :volvox)

  def library, do: Path.join(volvox(), "library")

  @doc "Every core module under library/, by module name."
  def all do
    root = library()

    root
    |> Path.join("**/*.lua")
    |> Path.wildcard()
    |> Enum.reject(&String.ends_with?(&1, "_test.lua"))
    |> Enum.map(&{module_name(root, &1), File.read!(&1)})
    |> Enum.reject(fn {_, src} -> src =~ ~r/require\(\s*"ffi"\s*\)/ end)
    |> Map.new()
  end

  @doc "The module name a file under `root` is required by."
  def module_name(root, path) do
    path
    |> Path.relative_to(root)
    |> Path.rootname()
    |> String.replace_suffix("/init", "")
    |> String.replace("/", ".")
  end

  @doc "A Lua file of this host, from priv/lua."
  def priv(name), do: File.read!(Path.join(:code.priv_dir(:volvox_server), "lua/" <> name))
end

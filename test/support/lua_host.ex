defmodule Moss.LuaHost do
  @moduledoc """
  The test host: the node's base Lua state plus `mono.spec` (from Arock's
  nomimono), `arock-log.ffi` over Exqlite, and `test/support/lua/test_host.lua`.
  Built once per test run and kept in `:persistent_term`.
  """
  alias Moss.Lua.{Ports, Sources}

  @here Path.expand("lua", __DIR__)

  def base do
    case :persistent_term.get(__MODULE__, nil) do
      nil ->
        lua = build()
        :persistent_term.put(__MODULE__, lua)
        lua

      lua ->
        lua
    end
  end

  defp build do
    spec = Path.join(Sources.core(), "packages/nomimono/rules/lua/lib/mono/spec.lua")

    extra = %{
      "mono.spec" => File.read!(spec),
      "arock-log.ffi" => File.read!(Path.join(@here, "ffi.lua"))
    }

    lua = Moss.Lua.build(extra)
    {_, lua} = Lua.eval!(lua, File.read!(Path.join(@here, "test_host.lua")))
    lua
  end

  @doc "`Moss.Lua.call/4` on the test base, with the __test functions bound."
  def call(fun, args, ports \\ []) do
    Moss.Lua.call(fun, args, ports, base: bind(base()))
  end

  defp bind(lua) do
    lua
    |> Lua.set!([:__test, :db_open], fn [_path], lua ->
      {:ok, conn} = Moss.Db.open(":memory:")
      h = System.unique_integer([:positive])
      Process.put({__MODULE__, h}, conn)
      {[h], lua}
    end)
    |> Lua.set!([:__test, :db_exec], fn [h | rest], lua ->
      Ports.db_exec(Process.get({__MODULE__, h}), rest, lua)
    end)
    |> Lua.set!([:__test, :read], fn [path] ->
      case File.read(path) do
        {:ok, s} -> [s]
        _ -> [nil]
      end
    end)
    |> Lua.set!([:__test, :write], fn [path, s] ->
      File.write!(path, s)
      []
    end)
    |> Lua.set!([:__test, :tmpname], fn _ ->
      [Path.join(System.tmp_dir!(), "moss-lua-#{System.unique_integer([:positive])}")]
    end)
    |> Lua.set!([:__test, :remove], fn [path] -> [File.rm(path) == :ok] end)
  end
end

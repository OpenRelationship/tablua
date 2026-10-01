defmodule Moss.Lua do
  @moduledoc """
  Arock Core in tv-labs `lua`, the Lua VM written in Elixir.

  One base state holds every core module, already loaded, plus the host glue
  (`priv/lua/host.lua`). It is built once and kept in `:persistent_term`, so
  every process reads it without a copy. A call binds the host's ports onto
  the base state, runs one `arock.*` function and drops the state: tv-labs
  lua has no garbage collector, so a state kept alive only grows.

  The sandbox stays on except for `load`, which `require` needs; the agent has
  no io, no os.execute and no filesystem.
  """
  alias Moss.Lua.{Ports, Sources}

  @key {__MODULE__, :base}

  # Loaded into the base state so a step pays for none of them.
  @core ~w(alog alog.schema alog.robot ports.json ports.call ports.jev ports.mercury)

  @doc "The base state, built on first use."
  def base do
    case :persistent_term.get(@key, nil) do
      nil ->
        lua = build()
        :persistent_term.put(@key, lua)
        lua

      lua ->
        lua
    end
  end

  @doc """
  A fresh base state: the core sources (plus `extra`, `name => source`), the
  prelude, the host glue, and the `preload` modules required.
  """
  def build(extra \\ %{}, preload \\ @core) do
    Lua.new(exclude: [[:load]])
    |> Lua.set!([:__sources], Map.merge(Sources.all(), extra))
    |> eval!(Sources.priv("prelude.lua"))
    |> eval!(Sources.priv("host.lua"))
    |> Lua.set!([:__preload], preload)
    |> eval!("for _, m in ipairs(__preload) do require(m) end __preload = nil")
  end

  defp eval!(lua, code) do
    {_, lua} = Lua.eval!(lua, code)
    lua
  end

  @doc "Parses an agent's source once; `call/4` runs it on each fresh state."
  def agent!(source) do
    case Lua.parse_chunk(source) do
      {:ok, chunk} -> chunk
      {:error, e} -> raise e
    end
  end

  @doc """
  Calls `arock.<fun>(args...)` on a fresh copy of the base state with the
  ports bound (see `Moss.Lua.Ports.bind/2`). With `agent: chunk`, the
  agent function is the first argument. Returns `{:ok, results}` with tables
  decoded, or `{:error, message}`.
  """
  def call(fun, args, ports, opts \\ []) do
    lua = Ports.bind(opts[:base] || base(), ports)

    {args, lua} =
      case opts[:agent] do
        nil ->
          {args, lua}

        chunk ->
          {[agent], lua} = Lua.eval!(lua, chunk)
          {[agent | args], lua}
      end

    {args, lua} = Enum.map_reduce(args, lua, &encode/2)

    case Lua.call_function(lua, [:arock, :call], [to_string(fun) | args]) do
      {:ok, results, lua} -> {:ok, Enum.map(results, &decode(lua, &1))}
      {:error, e, _lua} -> {:error, Exception.message(e)}
    end
  rescue
    e in [Lua.RuntimeException, Lua.CompilerException] -> {:error, Exception.message(e)}
  end

  defp encode(v, lua) when is_list(v) or is_map(v), do: Lua.encode!(lua, v)
  defp encode(v, lua), do: {v, lua}

  @doc "Decodes a returned value; tables become lists of `{key, value}` pairs."
  def decode(lua, {:tref, _} = t), do: Lua.decode!(lua, t)
  def decode(_lua, v), do: v

  @doc "A decoded Lua list (a table with keys 1..n) as an Elixir list."
  def list(pairs) when is_list(pairs), do: pairs |> Enum.sort() |> Enum.map(&elem(&1, 1))
  def list(nil), do: nil
end

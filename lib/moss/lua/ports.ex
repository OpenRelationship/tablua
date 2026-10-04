defmodule Moss.Lua.Ports do
  @moduledoc """
  The host's ports as Lua functions under `__host` (see `priv/lua/host.lua`).

    * `db_exec(sql, params) -> rows` on the connection given as `db:`, the
      arock-log's db port: rows are tables with NULL columns absent; params bind
      false as NULL.
    * `clock() -> "2026-09-28T00:00:00Z"`, `now() -> seconds`, `sleep(seconds)`.
    * `fetch{ method, url, headers, body, timeout } -> { status, body }` over
      Req; a transport failure raises. The ports.call record the core logs
      never holds the headers, so never the key.
    * `sha256(bytes) -> hex`: arock-log's content ids, from `:crypto` (tv-labs Lua's own hash is
      about 10 ms at 16 KB).
    * `key(name) -> string | nil`: a model key from the host (`Moss.Host.key/1`).
    * `service() -> { base, key, person } | nil`: Arock's service in the keys' place, for this call's computer
      (`Moss.Host.service/1`): on a node its token and the computer's person.

    * `exec{ cmd, cwd, files, timeout } -> { code, stdout, stderr, timed_out }`
      on a computer of its own (`Moss.Computer`, PROJECT.md §14),
      given as `computer:` (its id): never the node's shell or files.

  Only `db` and `computer` are per call; the rest are the same for every call.
  """
  alias Moss.{Db, Fetch}

  def bind(lua, ports) do
    lua
    |> Lua.set!([:__host, :clock], fn _ -> [clock()] end)
    |> Lua.set!([:__host, :now], fn _ -> [System.monotonic_time(:microsecond) / 1.0e6] end)
    |> Lua.set!([:__host, :sleep], &sleep/1)
    |> Lua.set!([:__host, :fetch], &fetch/2)
    |> Lua.set!([:__host, :key], fn [name | _] -> [Moss.Host.key(name)] end)
    |> bind_service(ports[:agent] || ports[:computer])
    |> Lua.set!([:__host, :sha256], fn [s | _] ->
      [Base.encode16(:crypto.hash(:sha256, s), case: :lower)]
    end)
    |> bind_db(ports[:db])
    |> bind_resolve(ports[:resolve])
    |> bind_computer(ports[:computer])
    |> bind_agent(ports[:agent])
  end

  # Arock's service for this call's computer, or nil: its base, the node's token and the computer's person
  defp bind_service(lua, id) do
    Lua.set!(lua, [:__host, :service], fn _, lua ->
      case Moss.Host.service(id) do
        nil ->
          {[nil], lua}

        svc ->
          {table, lua} = Lua.encode!(lua, Map.take(svc, ["base", "key", "person"]))
          {[table], lua}
      end
    end)
  end

  # the computer's own agent (Moss.Computer.Agent): the facts its stages are worked out from, and its log, read
  # and written through the computer, which owns the file
  defp bind_agent(lua, nil), do: lua

  defp bind_agent(lua, id) do
    lua
    |> Lua.set!([:__host, :agent_facts], fn [at | _], lua ->
      {table, lua} = Lua.encode!(lua, Moss.Computer.agent(id, :facts, [to_string(at)]))
      {[table], lua}
    end)
    |> Lua.set!([:__host, :agent_events], fn _, lua ->
      {table, lua} = Lua.encode!(lua, Moss.Computer.agent(id, :events, []))
      {[table], lua}
    end)
    # the harness's own tables (library/tabula): sql and its params, rows back; refused outside tabula_ tables
    |> Lua.set!([:__host, :agent_sql], fn [sql | rest], lua ->
      params =
        case rest do
          [{:tref, _} = t | _] -> Lua.decode!(lua, t) |> Enum.sort() |> Enum.map(fn {_, v} -> v end)
          _ -> []
        end

      case Moss.Computer.agent(id, :sql, [sql, params]) do
        {:ok, rows} ->
          {table, lua} = Lua.encode!(lua, rows)
          {[table], lua}

        {:error, why} ->
          {[nil, why], lua}
      end
    end)
    |> Lua.set!([:__host, :agent_append], fn [task, keyword, {:tref, _} = args, actor | _], lua ->
      args = Lua.decode!(lua, args) |> Enum.sort() |> Enum.map(fn {_, v} -> to_string(v) end)
      :ok = Moss.Computer.agent(id, :append, [task, keyword, args, actor])
      {[], lua}
    end)
  end

  defp bind_computer(lua, nil), do: lua

  defp bind_computer(lua, id) do
    Lua.set!(lua, [:__host, :exec], fn [{:tref, _} = t | _], lua ->
      req =
        Map.new(Lua.decode!(lua, t), fn {k, v} ->
          {k, if(k == "files", do: Map.new(v), else: v)}
        end)

      {table, lua} = Lua.encode!(lua, Moss.Computer.exec(id, req))
      {[table], lua}
    end)
  end

  # how a link is resolved: a function of the target, true or {false, why}
  defp bind_resolve(lua, nil), do: lua

  defp bind_resolve(lua, f) do
    Lua.set!(lua, [:__host, :resolve], fn [target | _] ->
      case f.(to_string(target)) do
        true -> [true]
        {false, why} -> [false, why]
      end
    end)
  end

  defp bind_db(lua, nil), do: lua
  defp bind_db(lua, conn), do: Lua.set!(lua, [:__host, :db_exec], &db_exec(conn, &1, &2))

  @doc "The db port over `conn`, as a Lua function body; shared with the test host."
  def db_exec(conn, [sql | rest], lua) do
    params = params(lua, List.first(rest))

    case Db.exec(conn, sql, params) do
      {:ok, rows} ->
        {table, lua} = Lua.encode!(lua, rows)
        {[table], lua}

      {:error, message} ->
        {:error, message, lua}
    end
  end

  # Positional params from a Lua list, holes as NULL.
  defp params(_lua, nil), do: []

  defp params(lua, {:tref, _} = t) do
    pairs = Lua.decode!(lua, t) |> Enum.filter(fn {k, _} -> is_integer(k) and k > 0 end)
    by = Map.new(pairs)
    n = pairs |> Enum.map(&elem(&1, 0)) |> Enum.max(fn -> 0 end)
    for i <- 1..n//1, do: Map.get(by, i)
  end

  defp sleep([seconds | _]) do
    Process.sleep(round(seconds * 1000))
    []
  end

  defp clock, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  defp fetch([{:tref, _} = t | _], lua) do
    req = Map.new(Lua.decode!(lua, t))

    case Fetch.request(req) do
      {:ok, status, body} ->
        {table, lua} = Lua.encode!(lua, %{"status" => status, "body" => body})
        {[table], lua}

      {:error, message} ->
        {:error, message, lua}
    end
  end
end

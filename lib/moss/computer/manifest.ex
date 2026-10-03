defmodule Moss.Computer.Manifest do
  @moduledoc """
  What a computer's manifests declare (Arock's feature `manifest`), read by arock-log's own Lua: `/home/manifest.org`
  lists the apps and the computer's tools, and each listed app's `apps/<app>/manifest.org` its own tools, named
  `<app>:<tool>`. An app folder not listed is not served and its tools do not run.

  Reach is asked in the manifest and granted only by the person: each yes is a `Grant Reach` event on the
  computer's log, for one request (NET and a host, MAIL and an address, ACCOUNT and an app), and a request
  removed takes its grant back (`Revoke Reach`, `revoke_dropped/2`). A tool's reach is what it asks and the person
  granted, both.
  """
  alias Moss.Computer.Disk
  alias Moss.Log

  @root "/home/manifest.org"

  @doc "The computer's manifest: `%{apps: [name], tools: %{name => tool}}`, tools of listed apps as `app:tool`."
  def read(disk) do
    root = full(disk, @root)

    app_tools =
      for app <- root.apps,
          tool <- full(disk, "/home/apps/#{app}/manifest.org").tools,
          into: %{},
          do: {"#{app}:#{tool.name}", %{tool | name: "#{app}:#{tool.name}", app: app}}

    %{apps: root.apps, tools: Map.merge(Map.new(root.tools, &{&1.name, &1}), app_tools)}
  end

  @doc "Whether the root manifest lists `app`."
  def listed?(disk, app), do: app in full(disk, @root).apps

  @doc "A tool by its name (`weather`, `plants:seed`), or nil."
  def tool(disk, name), do: read(disk).tools[name]

  @doc "The folder a tool runs in: its app's, or /home."
  def folder(%{app: nil}), do: "/home"
  def folder(%{app: app}), do: "/home/apps/" <> app

  @doc "Each request a tool makes, as `{reach, value}`: `{\"NET\", host}`, `{\"MAIL\", address}`, `{\"ACCOUNT\", app}`."
  def requests(tool) do
    Enum.map(tool.net, &{"NET", &1}) ++
      Enum.map(tool.mail, &{"MAIL", &1}) ++ if(tool.account, do: [{"ACCOUNT", tool.account}], else: [])
  end

  @doc "The requests of `tool` the person granted and has not taken back."
  def granted(disk, tool) do
    live = grants(disk)
    Enum.filter(requests(tool), fn {reach, value} -> MapSet.member?(live, {tool.name, reach, value}) end)
  end

  @doc "Every grant still standing on this computer's log, as `{tool, reach, value}`."
  def grants(disk) do
    Enum.reduce(Log.reach(disk.conn), MapSet.new(), fn
      {"Grant Reach", g}, acc -> MapSet.put(acc, g)
      {"Revoke Reach", g}, acc -> MapSet.delete(acc, g)
    end)
  end

  @doc "Takes back each standing grant whose request the manifests no longer make; the grants taken back."
  def revoke_dropped(disk, task) do
    asked = for {name, t} <- read(disk).tools, {r, v} <- requests(t), into: MapSet.new(), do: {name, r, v}
    dropped = MapSet.difference(grants(disk), asked) |> Enum.sort()

    for {tool, reach, value} <- dropped,
        do: :ok = Log.append(disk.conn, task, "Revoke Reach", [tool, reach, value], "host")

    dropped
  end

  @doc "`[]`, or the lines an agent's manifest is refused for (as `\"line: why\"`)."
  def check(text) do
    {:ok, [json]} = Moss.Lua.call("names", ["check", text], %{})
    list(Jason.decode!(json))
  end

  defp full(disk, path) do
    case Disk.read(disk, path) do
      {:ok, text} ->
        # read once per text, in the computer's own process: every request to an app asks
        hash = :erlang.md5(text)

        case Process.get({__MODULE__, path}) do
          {^hash, m} ->
            m

          _ ->
            {:ok, [json]} = Moss.Lua.call("names", ["full", text], %{})
            m = Jason.decode!(json)
            m = %{apps: list(m["apps"]), tools: Enum.map(list(m["tools"]), &tool_of/1)}
            Process.put({__MODULE__, path}, {hash, m})
            m
        end

      _ ->
        %{apps: [], tools: []}
    end
  end

  defp tool_of(t) do
    %{
      name: t["name"],
      app: nil,
      run: t["run"],
      description: t["description"],
      args: list(t["args"]),
      every: t["every"],
      on: t["on"],
      net: list(t["net"]),
      mail: list(t["mail"]),
      account: t["account"],
      ask: t["ask"] == true,
      publish: t["publish"] == true,
      from: t["from"],
      output: t["output"]
    }
  end

  # arock-log's JSON writes an empty list as {}
  defp list(l) when is_list(l), do: l
  defp list(_), do: []
end

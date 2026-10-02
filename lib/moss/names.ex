defmodule Moss.Names do
  @moduledoc """
  The node's names (Arock's feature `manifest`): every computer, app, tool, org entry and letter has one
  `org:` address, and this registry is how the node resolves one without waking the computer it names. The
  manifests are the computers' zone files: a write of `/home/manifest.org` (the computer's apps and tools) or
  `/home/apps/<app>/manifest.org` (an app's tools) replaces the names it declared (`Moss.Computer.Disk`).

      org:fern                    the computer
      org:fern/plants             an app, listed in fern's root manifest
      org:fern/weather            a tool in the root manifest
      org:fern/plants/seed        a tool in the plants app's manifest
      org:fern/entries/e12        an org entry, by its ID
      org:fern/mail/7             a letter fern sent or was sent, by its number in the post

  `org:` is a scheme, never a domain: `https://fern.org/` is someone's website and is never resolved here.
  A manifest is read by alog's own Lua (`arock.names`), so its rules are written once. One process per node
  holds the names in the node's `names.sqlite`.
  """
  use GenServer
  alias Moss.Db

  @reserved ~w(entries mail)

  def computer(id), do: GenServer.call(__MODULE__, {:put, ["org:" <> id], id, "computer", "computer"})

  @doc "The names a manifest at `path` on computer `id` declares, replacing what it declared before; nil when it is gone."
  def manifest(id, path, text) do
    case scope(path) do
      nil -> :ok
      app -> GenServer.call(__MODULE__, {:manifest, id, path, app, text})
    end
  end

  @doc "Forgets what the manifests at or under `path` on computer `id` declared (removed or moved away)."
  def gone(id, path), do: GenServer.call(__MODULE__, {:gone, id, path})

  def entry(id, entry_id), do: GenServer.call(__MODULE__, {:put, ["org:#{id}/entries/#{entry_id}"], id, "entry", "org"})

  @doc "`{:ok, kind}` (computer, app, tool, entry, letter) or `{:error, why}`."
  def resolve(address), do: GenServer.call(__MODULE__, {:resolve, address})

  # "/home/manifest.org" is the computer's own; "/home/apps/<app>/manifest.org" an app's
  defp scope("/home/manifest.org"), do: :root

  defp scope(path) do
    case Regex.run(~r"\A/home/apps/([a-z0-9][a-z0-9-]{0,63})/manifest\.org\z", path) do
      [_, app] -> app
      _ -> nil
    end
  end

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    path = opts[:path] || Path.join(Application.fetch_env!(:moss, :work_dir), "names.sqlite")
    File.mkdir_p!(Path.dirname(path))
    {:ok, conn} = Db.open(path)

    {:ok, _} =
      Db.exec(
        conn,
        "create table if not exists names (address text primary key, computer text not null, " <>
          "kind text not null, source text not null, at integer not null)",
        []
      )

    {:ok, conn}
  end

  @impl true
  def handle_call({:put, addresses, id, kind, source}, _from, conn) do
    for a <- addresses, do: put(conn, a, id, kind, source)
    {:reply, :ok, conn}
  end

  def handle_call({:manifest, id, path, app, text}, _from, conn) do
    source = "manifest:" <> path
    {:ok, _} = Db.exec(conn, "delete from names where computer = ? and source = ?", [id, source])

    if text do
      %{"apps" => apps, "tools" => tools} = read(text)
      base = if app == :root, do: "org:" <> id, else: "org:#{id}/#{app}"

      if app == :root,
        do: for(a <- apps, a not in @reserved, do: put(conn, "org:#{id}/#{a}", id, "app", source))

      for t <- tools, t not in @reserved, do: put(conn, "#{base}/#{t}", id, "tool", source)
    end

    {:reply, :ok, conn}
  end

  def handle_call({:gone, id, path}, _from, conn) do
    {:ok, _} =
      Db.exec(
        conn,
        "delete from names where computer = ?1 and (source = 'manifest:' || ?2 or " <>
          "(source >= 'manifest:' || ?2 || '/' and source < 'manifest:' || ?2 || '0'))",
        [id, path]
      )

    {:reply, :ok, conn}
  end

  def handle_call({:resolve, address}, _from, conn), do: {:reply, lookup(conn, address), conn}

  defp lookup(conn, address) do
    with {:ok, parts} <- parse(address) do
      case {Db.exec(conn, "select kind from names where address = ?", [address]), parts} do
        {{:ok, [%{"kind" => kind}]}, _} ->
          {:ok, kind}

        {_, [c, "mail", n]} ->
          if letter?(c, n), do: {:ok, "letter"}, else: nothing(address)

        _ ->
          nothing(address)
      end
    end
  end

  defp nothing(address), do: {:error, "the address #{address} names nothing on this node"}

  defp parse(address) when is_binary(address) do
    case Moss.Lua.call("names", ["address", address], %{}) do
      {:ok, [nil, why]} -> {:error, why}
      {:ok, [parts | _]} when is_list(parts) -> {:ok, Moss.Lua.list(parts)}
      _ -> {:error, "an address is org:<computer>/<path>"}
    end
  end

  defp parse(_), do: {:error, "an address is org:<computer>/<path>"}

  defp letter?(c, n) do
    case Integer.parse(n) do
      {id, ""} -> Moss.Mail.party?(c, id)
      _ -> false
    end
  end

  defp read(text) do
    {:ok, [pairs]} = Moss.Lua.call("names", ["manifest", text], %{})
    m = Map.new(pairs)
    %{"apps" => Moss.Lua.list(m["apps"]), "tools" => Moss.Lua.list(m["tools"])}
  end

  defp put(conn, address, id, kind, source) do
    {:ok, _} =
      Db.exec(
        conn,
        "insert or replace into names (address, computer, kind, source, at) values (?, ?, ?, ?, ?)",
        [address, id, kind, source, System.os_time(:second)]
      )
  end
end

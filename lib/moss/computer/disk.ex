defmodule Moss.Computer.Disk do
  @moduledoc """
  An agent's computer's filesystem, on the computer's log (`Moss.Log`, Arock's
  PROJECT.md §15): every change is an alog event (`Make Folder`, `Write File`,
  `Delete File`, `Move File`) in the computer's own SQLite file, and `nodes`
  is a view over the files alog folds from them, so what the computer did to
  its files is history, not overwritten rows. The file is the whole disk, so
  it sleeps to the object store and wakes as the computer does.

      {:ok, disk} = Disk.open(path)
      Disk.write(disk, "/notes/todo.txt", "buy moss")   # its folders made as needed
      Disk.read(disk, "/notes/todo.txt")                 # {:ok, "buy moss"}
      Disk.list(disk, "/notes")                          # {:ok, [%{name: "todo.txt", dir: false, size: 8, mtime: ...}]}

  A disk is its connection, the computer it belongs to (the log's task) and
  who its changes are by (`actor`: "agent", "user" or "host"). `keep/3` and
  `kept/3` hold the computer's own state beside the files.
  Paths are normalised (`.`, `..`, repeated slashes) and never leave `/`.
  """
  alias Moss.{Db, Log}

  defstruct [:conn, :task, actor: "agent"]

  @kept "create table if not exists kept (key text primary key, value blob not null)"

  @nodes "create view if not exists nodes as " <>
           "select path, dir, data, cast(strftime('%s', at) as integer) as mtime from entries"

  @max_bytes 256 * 1024 * 1024

  @doc """
  Opens the disk at `path` for computer `task` (the file's name by default),
  its changes by the host until `actor` is set. Its size is held to config
  `disk_max_bytes` (#{div(256 * 1024 * 1024, 1_048_576)} MB), the log with it: past it, a write is
  `{:error, "database or disk is full"}`. A disk from before the log, a
  `nodes` table, moves onto it once.
  """
  def open(path, task \\ nil) do
    File.mkdir_p!(Path.dirname(path))
    max = Application.get_env(:moss, :disk_max_bytes, @max_bytes)
    task = task || String.replace(Path.basename(path, ".sqlite"), ~r/[^\w.:-]/, "-")

    with {:ok, conn} <- Db.open(path),
         disk = %__MODULE__{conn: conn, task: task, actor: "host"},
         {:ok, _} <- Db.exec(conn, "pragma synchronous = normal", []),
         {:ok, _} <- replicated(conn),
         {:ok, _} <- Db.exec(conn, @kept, []),
         :ok <- Log.open(conn),
         :ok <- from_nodes(disk),
         :ok <- root(disk),
         {:ok, _} <- Db.exec(conn, @nodes, []),
         {:ok, [%{"page_size" => page}]} <- Db.exec(conn, "pragma page_size", []),
         {:ok, _} <- Db.exec(conn, "pragma max_page_count = #{div(max, page)}", []) do
      {:ok, disk}
    end
  end

  @doc """
  Closes the disk. Kept whole (`Moss.Litestream.mode/0` is `:whole`), its WAL
  is folded in first, so the file alone is the disk; streamed by Litestream,
  the file is only closed: Litestream owns its checkpoints and its WAL.
  """
  def close(disk) do
    if Moss.Litestream.mode() == :litestream,
      do: Exqlite.Sqlite3.close(disk.conn),
      else: Db.checkpoint_and_close(disk.conn)
  end

  # alog's replicated settings (alog.LITESTREAM) when Litestream streams the file: WAL and busy_timeout are
  # Db.open's, synchronous normal is every disk's, and Litestream alone checkpoints
  defp replicated(conn) do
    if Moss.Litestream.mode() == :litestream,
      do: Db.exec(conn, "pragma wal_autocheckpoint = 0", []),
      else: {:ok, []}
  end

  @doc """
  Gives back the pages SQLite keeps cached for this disk, for a computer at rest: an event reads and writes a
  dozen of the log's tables, and their pages held between commands cost an awake computer about 130 KB.
  """
  def rest(disk) do
    {:ok, _} = Db.exec(disk.conn, "pragma shrink_memory", [])
    :ok
  end

  # a new disk's root, by the host
  defp root(disk) do
    case Db.exec(disk.conn, "select 1 as x from files where path = '/'", []) do
      {:ok, [_]} -> :ok
      {:ok, []} -> log(disk, "Make Folder", ["/"])
    end
  end

  # A disk from before the log: its rows replayed as the host's events, folders first and then files, each at
  # its own mtime, and the table dropped, all in one transaction.
  defp from_nodes(disk) do
    case Db.exec(
           disk.conn,
           "select 1 as x from sqlite_master where name = 'nodes' and type = 'table'",
           []
         ) do
      {:ok, []} ->
        :ok

      {:ok, [_]} ->
        conn = disk.conn
        {:ok, _} = Db.exec(conn, "begin immediate", [])

        {:ok, rows} =
          Db.exec(conn, "select path, dir, data, mtime from nodes order by dir desc, path", [])

        for r <- rows do
          at = r["mtime"] |> DateTime.from_unix!() |> DateTime.to_iso8601()

          {kw, args} =
            if r["dir"] == 1,
              do: {"Make Folder", [r["path"]]},
              else: {"Write File", [r["path"], Map.get(r, "data", "")]}

          :ok = Log.append(conn, disk.task, kw, args, "host", at)
        end

        {:ok, _} = Db.exec(conn, "drop table nodes", [])
        {:ok, _} = Db.exec(conn, "commit", [])
        :ok
    end
  end

  # one event on the computer's log, by the disk's actor
  defp log(disk, keyword, args) do
    with :ok <- Log.append(disk.conn, disk.task, keyword, args, disk.actor),
         do: home_changed(disk, if(keyword == "Move File", do: args, else: Enum.take(args, 1)))
  end

  # A change under /home by anyone but the person using the app (whose requests write its databases) is told on
  # `home:<id>`, so the app's window reloads (MossWeb.ComputerLive).
  defp home_changed(%{task: id, actor: actor}, paths) when is_binary(id) and actor != "user" do
    if Enum.any?(paths, &(&1 == "/home" or String.starts_with?(&1, "/home/"))),
      do: Phoenix.PubSub.broadcast(Moss.PubSub, "home:" <> id, {:home_changed, id})

    :ok
  end

  defp home_changed(_, _), do: :ok

  @doc "The absolute, normalised form of `path`, taken from `cwd` when relative."
  def norm(path, cwd \\ "/") do
    full = if String.starts_with?(path, "/"), do: path, else: cwd <> "/" <> path

    parts =
      full
      |> String.split("/", trim: true)
      |> Enum.reduce([], fn
        ".", acc -> acc
        "..", [] -> []
        "..", [_ | rest] -> rest
        part, acc -> [part | acc]
      end)
      |> Enum.reverse()

    "/" <> Enum.join(parts, "/")
  end

  defp own_stat(disk, path) do
    case Db.exec(
           disk.conn,
           "select dir, length(data) as size, mtime from nodes where path = ?1",
           [
             norm(path)
           ]
         ) do
      {:ok, [row]} -> {:ok, %{dir: row["dir"] == 1, size: row["size"] || 0, mtime: row["mtime"]}}
      {:ok, []} -> {:error, :enoent}
    end
  end

  defp own_read(disk, path) do
    case Db.exec(disk.conn, "select dir, data from nodes where path = ?1", [norm(path)]) do
      {:ok, [%{"dir" => 1}]} -> {:error, :eisdir}
      {:ok, [row]} -> {:ok, Map.get(row, "data", "")}
      {:ok, []} -> {:error, :enoent}
    end
  end

  def stat(disk, path), do: own_stat(disk, norm(path))
  def read(disk, path), do: own_read(disk, norm(path))

  @doc "A folder's entries, sorted by name."
  def list(disk, path), do: own_list(disk, norm(path))

  def write(disk, path, data) do
    path = norm(path)

    with :ok <- mkdir_p(disk, Path.dirname(path)),
         {:ok, %{dir: false}} <- file_or_none(disk, path) do
      log(disk, "Write File", [path, data])
    else
      {:ok, %{dir: true}} -> {:error, :eisdir}
      other -> other
    end
  end

  defp file_or_none(disk, path) do
    case stat(disk, path) do
      {:error, :enoent} -> {:ok, %{dir: false}}
      found -> found
    end
  end

  def mkdir(disk, path) do
    path = norm(path)

    case {stat(disk, Path.dirname(path)), stat(disk, path)} do
      {{:ok, %{dir: true}}, {:ok, %{dir: true}}} -> :ok
      {{:ok, %{dir: true}}, {:ok, _}} -> {:error, :eexist}
      {{:ok, %{dir: true}}, {:error, :enoent}} -> log(disk, "Make Folder", [path])
      {{:ok, _}, _} -> {:error, :enotdir}
      {error, _} -> error
    end
  end

  def mkdir_p(_disk, "/"), do: :ok

  def mkdir_p(disk, path) do
    case stat(disk, path) do
      {:ok, %{dir: true}} -> :ok
      _ -> with :ok <- mkdir_p(disk, Path.dirname(norm(path))), do: mkdir(disk, path)
    end
  end

  defp own_list(disk, path) do
    path = norm(path)

    case stat(disk, path) do
      {:ok, %{dir: true}} ->
        prefix = if path == "/", do: "/", else: path <> "/"

        {:ok, rows} =
          Db.exec(
            disk.conn,
            "select path, dir, length(data) as size, mtime from nodes " <>
              "where substr(path, 1, length(?1)) = ?1 and path <> '/' and instr(substr(path, length(?1) + 1), '/') = 0 " <>
              "order by path",
            [prefix]
          )

        {:ok,
         Enum.map(rows, fn r ->
           %{
             name: Path.basename(r["path"]),
             dir: r["dir"] == 1,
             size: r["size"] || 0,
             mtime: r["mtime"]
           }
         end)}

      {:ok, _} ->
        {:error, :enotdir}

      error ->
        error
    end
  end

  @doc "Removes a file, or a folder with everything in it when `all` is true (an empty one otherwise)."
  def remove(disk, path, all \\ false) do
    path = norm(path)
    remove_own(disk, path, all)
  end

  defp remove_own(disk, path, all) do
    case {path, stat(disk, path)} do
      {"/", _} ->
        {:error, :eperm}

      {_, {:ok, %{dir: true}}} ->
        {:ok, kids} = list(disk, path)

        if kids != [] and not all,
          do: {:error, :enotempty},
          else: log(disk, "Delete File", [path])

      {_, {:ok, _}} ->
        log(disk, "Delete File", [path])

      {_, error} ->
        error
    end
  end

  @doc "Moves a file or a folder (and all under it) to `to`, replacing a file there."
  def rename(disk, from, to) do
    {from, to} = {norm(from), norm(to)}

    with {:ok, _} <- stat(disk, from),
         {:ok, %{dir: true}} <- stat(disk, Path.dirname(to)),
         :ok <- if(String.starts_with?(to <> "/", from <> "/"), do: {:error, :einval}, else: :ok) do
      log(disk, "Move File", [from, to])
    else
      {:ok, _} -> {:error, :enotdir}
      error -> error
    end
  end

  @doc "Keeps a term beside the files (the terminal's lines, the browser's tabs), for when the computer wakes."
  def keep(disk, key, term) do
    {:ok, _} =
      Db.exec(disk.conn, "insert or replace into kept (key, value) values (?1, ?2)", [
        key,
        {:blob, :erlang.term_to_binary(term)}
      ])

    :ok
  end

  def kept(disk, key, default) do
    case Db.exec(disk.conn, "select value from kept where key = ?1", [key]) do
      {:ok, [%{"value" => v}]} -> :erlang.binary_to_term(v, [:safe])
      _ -> default
    end
  end
end

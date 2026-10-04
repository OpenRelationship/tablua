defmodule Moss.Computer.Disk do
  @moduledoc """
  An agent's computer's filesystem, on the computer's log (`Moss.Log`, Arock's
  PROJECT.md §15): every change is an arock-log event (`Make Folder`, `Write File`,
  `Delete File`, `Move File`) in the computer's own SQLite file, and `nodes`
  is a view over the files arock-log folds from them, so what the computer did to
  its files is history, not overwritten rows. The file is the whole disk, so
  it sleeps to the object store and wakes as the computer does.

      {:ok, disk} = Disk.open(path)
      Disk.write(disk, "/notes/todo.txt", "buy moss")   # its folders made as needed
      Disk.read(disk, "/notes/todo.txt")                 # {:ok, "buy moss"}
      Disk.list(disk, "/notes")                          # {:ok, [%{name: "todo.txt", dir: false, size: 8, mtime: ...}]}

  A disk is its connection, the computer it belongs to (the log's task) and
  who its changes are by (`actor`: "agent", "user" or "host"; `app`: true when an app's page code makes them for the person using the app, with the agent's rights, not the person's). Its `kept` table
  holds the computer's own state beside the files (`Moss.Computer.Session`).

  The agent's databases (`db.open` in Lua, `Moss.Sql.Store`) are entries
  too: `ls` and `stat` show them, `cat` reads a summary, `rm` removes one;
  writing, moving or copying a file onto one is refused, and a database is
  never moved.
  Paths are normalised (`.`, `..`, repeated slashes) and never leave `/`.
  """
  alias Moss.{Db, Log}
  alias Moss.Computer.{Kinds, Named}
  alias Moss.Sql.Store

  # `under`: the task its events go under for a while (an agent's step, while its commands run), the computer's own
  # task when nil; `task` stays the computer it belongs to
  defstruct [:conn, :task, :under, actor: "agent", app: false]

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
         :ok <- Store.setup(conn),
         :ok <- from_nodes(disk),
         :ok <- root(disk),
         {:ok, _} <- Db.exec(conn, @nodes, []),
         {:ok, [%{"page_size" => page}]} <- Db.exec(conn, "pragma page_size", []),
         {:ok, _} <- Db.exec(conn, "pragma max_page_count = #{div(max, page)}", []) do
      {:ok, disk}
    end
  end

  @doc """
  Closes the disk. Kept whole (`Moss.Host.streamed?/0` is false), its WAL
  is folded in first, so the file alone is the disk; streamed by Litestream,
  the file is only closed: Litestream owns its checkpoints and its WAL.
  """
  def close(disk) do
    if Moss.Host.streamed?(),
      do: Exqlite.Sqlite3.close(disk.conn),
      else: Db.checkpoint_and_close(disk.conn)
  end

  @doc """
  The disk whole at `out`, while it is open (`vacuum into`, which leaves the WAL and Litestream alone): a sleeping
  computer's snapshot. It keeps the file's `user_version`, the computer's wake count (`stamp/2`).
  """
  def snapshot(disk, out) do
    File.rm(out)
    with {:ok, _} <- Db.exec(disk.conn, "vacuum into ?", [out]), do: :ok
  end

  @doc """
  Marks the file at `path` (made if missing) as the computer's `gen`th wake, its `user_version`, and leaves it whole:
  a woken computer's chain of segments is named by it, and its snapshot carries it (the host's, `Moss.Host.cut/1`).
  """
  def stamp(path, gen) when is_integer(gen) and gen > 0 do
    with {:ok, conn} <- Db.open(path),
         {:ok, _} <- Db.exec(conn, "pragma user_version = #{gen}", []),
         do: Db.checkpoint_and_close(conn)
  end

  # arock-log's replicated settings (alog.LITESTREAM) when Litestream streams the file: WAL and busy_timeout are
  # Db.open's, synchronous normal is every disk's, and Litestream alone checkpoints
  defp replicated(conn) do
    if Moss.Host.streamed?(),
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
    with :ok <- Log.append(disk.conn, disk.under || disk.task, keyword, args, disk.actor),
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

  def stat(disk, path) do
    path = norm(path)

    case own_stat(disk, path) do
      {:error, :enoent} -> Store.stat(disk.conn, path) || {:error, :enoent}
      found -> found
    end
  end

  def read(disk, path) do
    path = norm(path)

    case own_read(disk, path) do
      {:error, :enoent} ->
        if Store.exists?(disk.conn, path),
          do: {:ok, Store.describe(disk.conn, path)},
          else: {:error, :enoent}

      found ->
        found
    end
  end

  @database "is a database (change it with SQL through db.open in Lua; rm removes it)"

  defp database?(disk, path), do: Store.exists?(disk.conn, path)

  @doc "A folder's entries, sorted by name."
  def list(disk, path), do: own_list(disk, norm(path))

  def write(disk, path, data) do
    path = norm(path)

    with :ok <- kind(disk, path, &Kinds.file/1),
         :ok <- Named.check(disk, path, data),
         :ok <- mkdir_p(disk, Path.dirname(path)),
         {:ok, %{dir: false} = st} <- file_or_none(disk, path),
         false <- Map.get(st, :db, false),
         {:ok, data} <- Moss.Computer.OrgFile.kept(disk, path, data) do
      with :ok <- log(disk, "Write File", [path, data]), do: Named.written(disk, path, data)
    else
      true -> {:error, @database}
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
      {{:ok, %{dir: true}}, {:ok, %{dir: true}}} ->
        :ok

      {{:ok, %{dir: true}}, {:ok, _}} ->
        {:error, :eexist}

      {{:ok, %{dir: true}}, {:error, :enoent}} ->
        with :ok <- kind(disk, path, &Kinds.folder/1), do: log(disk, "Make Folder", [path])

      {{:ok, _}, _} ->
        {:error, :enotdir}

      {error, _} ->
        error
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

        files =
          Enum.map(rows, fn r ->
            %{
              name: Path.basename(r["path"]),
              dir: r["dir"] == 1,
              size: r["size"] || 0,
              mtime: r["mtime"]
            }
          end)

        dbs =
          for p <- Store.list(disk.conn, prefix),
              {:ok, st} = Store.stat(disk.conn, p),
              do: %{name: Path.basename(p), dir: false, size: st.size, mtime: st.mtime}

        {:ok, Enum.sort_by(files ++ dbs, & &1.name)}

      {:ok, _} ->
        {:error, :enotdir}

      error ->
        error
    end
  end

  @doc "Removes a file, or a folder with everything in it when `all` is true (an empty one otherwise)."
  def remove(disk, path, all \\ false) do
    path = norm(path)
    with :ok <- Moss.Computer.Writs.guard(disk, path), do: remove_own(disk, path, all)
  end

  defp remove_own(disk, path, all) do
    case {path, stat(disk, path)} do
      {"/", _} ->
        {:error, :eperm}

      {_, {:ok, %{db: true}}} ->
        Store.remove(disk.conn, path)

      {_, {:ok, %{dir: true}}} ->
        {:ok, kids} = list(disk, path)

        if kids != [] and not all,
          do: {:error, :enotempty},
          else: with(:ok <- log(disk, "Delete File", [path]), do: Named.removed(disk, path))

      {_, {:ok, _}} ->
        with :ok <- log(disk, "Delete File", [path]), do: Named.removed(disk, path)

      {_, error} ->
        error
    end
  end

  @doc "Moves a file or a folder (and all under it) to `to`, replacing a file there."
  def rename(disk, from, to) do
    {from, to} = {norm(from), norm(to)}

    with :ok <- Moss.Computer.Writs.guard(disk, from),
         :ok <- Moss.Computer.Writs.guard(disk, to),
         false <- database?(disk, from) or database?(disk, to),
         {:ok, st} <- stat(disk, from),
         {:ok, %{dir: true}} <- stat(disk, Path.dirname(to)),
         :ok <- if(String.starts_with?(to <> "/", from <> "/"), do: {:error, :einval}, else: :ok),
         :ok <- movable(disk, from, to, st),
         :ok <- Named.check_moved(disk, from, to) do
      with :ok <- log(disk, "Move File", [from, to]), do: Named.moved(disk, from, to)
    else
      true -> {:error, @database}
      {:ok, _} -> {:error, :enotdir}
      error -> error
    end
  end

  # the six kinds (Kinds) hold for the agent and the person; the host writes where it must, and the person's writs
  # (Arock feature notes) are kept in /home/writs, theirs and the host's alone: an agent reads them and writes none
  defp kind(%{actor: "host"}, _path, _check), do: :ok
  defp kind(%{actor: "user", app: false}, "/home/writs", _check), do: :ok
  defp kind(%{actor: "user", app: false}, "/home/writs/" <> _, _check), do: :ok
  defp kind(_disk, path, check), do: check.(path)

  # a folder moves only where every file under it may go
  defp movable(disk, _from, to, %{dir: false}), do: kind(disk, to, &Kinds.file/1)

  defp movable(disk, from, to, %{dir: true}) do
    {:ok, rows} =
      Db.exec(
        disk.conn,
        "select path, dir from nodes where path >= ?1 || '/' and path < ?1 || '0'",
        [from]
      )

    Enum.reduce_while([%{"path" => from, "dir" => 1} | rows], :ok, fn r, :ok ->
      dest = to <> binary_part(r["path"], byte_size(from), byte_size(r["path"]) - byte_size(from))
      check = if r["dir"] == 1, do: &Kinds.folder/1, else: &Kinds.file/1

      case kind(disk, dest, check) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  @doc "Tells the app's window that `paths` changed (a database's write, by `Moss.Computer.Script.Sql`)."
  def changed(disk, paths), do: home_changed(disk, paths)
end

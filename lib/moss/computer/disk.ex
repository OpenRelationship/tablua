defmodule Moss.Computer.Disk do
  @moduledoc """
  An agent's computer's filesystem: one table in the computer's own SQLite
  file, a row per file or folder by its absolute path. The file is the whole
  disk, so it sleeps to the object store and wakes as the computer does.

      {:ok, disk} = Disk.open(path)
      Disk.write(disk, "/notes/todo.txt", "buy moss")   # its folders made as needed
      Disk.read(disk, "/notes/todo.txt")                 # {:ok, "buy moss"}
      Disk.list(disk, "/notes")                          # {:ok, [%{name: "todo.txt", dir: false, size: 8, mtime: ...}]}

  `keep/3` and `kept/3` hold the computer's own state beside the files.
  Paths are normalised (`.`, `..`, repeated slashes) and never leave `/`.
  """
  alias Moss.Db

  @schema """
  create table if not exists nodes (
    path  text primary key,
    dir   integer not null,
    data  blob,
    mtime integer not null
  );
  insert or ignore into nodes (path, dir, data, mtime) values ('/', 1, null, 0);
  create table if not exists kept (key text primary key, value blob not null);
  """

  @max_bytes 256 * 1024 * 1024

  @doc "Opens the disk at `path`, its size held to config `disk_max_bytes` (#{div(256 * 1024 * 1024, 1_048_576)} MB): past it, a write is `{:error, \"database or disk is full\"}`."
  def open(path) do
    File.mkdir_p!(Path.dirname(path))
    max = Application.get_env(:moss, :disk_max_bytes, @max_bytes)

    with {:ok, conn} <- Db.open(path),
         {:ok, _} <- Db.exec(conn, @schema, []),
         {:ok, [%{"page_size" => page}]} <- Db.exec(conn, "pragma page_size", []),
         {:ok, _} <- Db.exec(conn, "pragma max_page_count = #{div(max, page)}", []) do
      {:ok, conn}
    end
  end

  def close(disk), do: Db.checkpoint_and_close(disk)

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
    case Db.exec(disk, "select dir, length(data) as size, mtime from nodes where path = ?1", [
           norm(path)
         ]) do
      {:ok, [row]} -> {:ok, %{dir: row["dir"] == 1, size: row["size"] || 0, mtime: row["mtime"]}}
      {:ok, []} -> {:error, :enoent}
    end
  end

  defp own_read(disk, path) do
    case Db.exec(disk, "select dir, data from nodes where path = ?1", [norm(path)]) do
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
         {:ok, _} <-
           Db.exec(
             disk,
             "insert into nodes (path, dir, data, mtime) values (?1, 0, ?2, ?3) " <>
               "on conflict (path) do update set data = ?2, mtime = ?3 where dir = 0",
             [path, {:blob, data}, now()]
           ),
         {:ok, %{dir: false}} <- stat(disk, path) do
      :ok
    else
      {:ok, %{dir: true}} -> {:error, :eisdir}
      other -> other
    end
  end

  def mkdir(disk, path) do
    path = norm(path)

    case stat(disk, Path.dirname(path)) do
      {:ok, %{dir: true}} ->
        case Db.exec(disk, "insert or ignore into nodes (path, dir, mtime) values (?1, 1, ?2)", [
               path,
               now()
             ]) do
          {:ok, _} ->
            if match?({:ok, %{dir: true}}, stat(disk, path)), do: :ok, else: {:error, :eexist}

          other ->
            other
        end

      {:ok, _} ->
        {:error, :enotdir}

      error ->
        error
    end
  end

  def mkdir_p(_disk, "/"), do: :ok

  def mkdir_p(disk, path) do
    with :ok <- mkdir_p(disk, Path.dirname(norm(path))), do: mkdir(disk, path)
  end

  defp own_list(disk, path) do
    path = norm(path)

    case stat(disk, path) do
      {:ok, %{dir: true}} ->
        prefix = if path == "/", do: "/", else: path <> "/"

        {:ok, rows} =
          Db.exec(
            disk,
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

        if kids != [] and not all do
          {:error, :enotempty}
        else
          {:ok, _} =
            Db.exec(
              disk,
              "delete from nodes where path = ?1 or substr(path, 1, length(?1) + 1) = ?1 || '/'",
              [path]
            )

          :ok
        end

      {_, {:ok, _}} ->
        {:ok, _} = Db.exec(disk, "delete from nodes where path = ?1", [path])
        :ok

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
      {:ok, _} = Db.exec(disk, "begin", [])
      {:ok, _} = Db.exec(disk, "delete from nodes where path = ?1 and dir = 0", [to])

      {:ok, _} =
        Db.exec(
          disk,
          "update nodes set path = ?2 || substr(path, length(?1) + 1), mtime = ?3 " <>
            "where path = ?1 or substr(path, 1, length(?1) + 1) = ?1 || '/'",
          [from, to, now()]
        )

      {:ok, _} = Db.exec(disk, "commit", [])
      :ok
    else
      {:ok, _} -> {:error, :enotdir}
      error -> error
    end
  end

  @doc "Keeps a term beside the files (the terminal's lines, the browser's tabs), for when the computer wakes."
  def keep(disk, key, term) do
    {:ok, _} =
      Db.exec(disk, "insert or replace into kept (key, value) values (?1, ?2)", [
        key,
        {:blob, :erlang.term_to_binary(term)}
      ])

    :ok
  end

  def kept(disk, key, default) do
    case Db.exec(disk, "select value from kept where key = ?1", [key]) do
      {:ok, [%{"value" => v}]} -> :erlang.binary_to_term(v, [:safe])
      _ -> default
    end
  end

  defp now, do: System.os_time(:second)
end

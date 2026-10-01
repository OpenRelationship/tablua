defmodule Moss.Computer.Script.Sql do
  @moduledoc """
  A script's databases (`db.open("app.db")` in Lua): each one is a SQLite file
  on the computer's own disk, loaded into memory for the run and written back
  when the script closes it or the run ends. So a database sleeps with its
  computer, counts against its disk, and never touches a node file.

  Inside, SQL is the script's: tables, indexes, views, triggers, transactions.
  `attach`, `detach` and every `pragma` are refused, so a script reaches no
  other database and cannot lift its own limit of #{div(64 * 1024 * 1024, 1_048_576)} MB. A run holds at most
  #{8} open databases. The connections live in the run's own process; when it
  is killed they go with it, unsaved.
  """
  alias Exqlite.Sqlite3
  alias Moss.Computer.Disk

  @max_bytes 64 * 1024 * 1024
  @max_open 8

  @doc "Opens `path` (a file, or a new one) and returns its handle."
  def open(disk, path) do
    dbs = dbs()

    cond do
      map_size(dbs) >= @max_open ->
        {:error, "too many open databases (#{@max_open})"}

      true ->
        with {:ok, bytes} <- existing(disk, path),
             {:ok, conn} <- Sqlite3.open(":memory:"),
             :ok <- load(conn, bytes),
             :ok <- Sqlite3.execute(conn, "pragma max_page_count = #{div(@max_bytes, 4096)}"),
             :ok <- Sqlite3.set_authorizer(conn, [:attach, :detach, :pragma]) do
          h = Process.get(:db_next, 1)
          Process.put(:db_next, h + 1)
          Process.put(:dbs, Map.put(dbs, h, %{conn: conn, path: path, dirty: false}))
          {:ok, h}
        end
    end
  end

  @doc "Runs `sql` with `params`; the rows of a query, or the count of rows it changed."
  def exec(h, sql, params) do
    with {:ok, db} <- fetch(h),
         {:ok, rows} <- Moss.Db.exec(db.conn, sql, Enum.map(params, &param/1)) do
      changes =
        case Sqlite3.changes(db.conn) do
          {:ok, n} -> n
          _ -> 0
        end

      unless reads?(sql), do: Process.put(:dbs, Map.put(dbs(), h, %{db | dirty: true}))
      {:ok, rows, changes}
    end
  end

  @doc "Writes a changed database back to its file on the disk."
  def save(disk, h) do
    with {:ok, db} <- fetch(h) do
      if db.dirty, do: write(disk, h, db), else: :ok
    end
  end

  @doc "Saves and closes one database."
  def close(disk, h) do
    with {:ok, db} <- fetch(h) do
      result = if db.dirty, do: write(disk, h, db), else: :ok
      Sqlite3.close(db.conn)
      Process.put(:dbs, Map.delete(dbs(), h))
      result
    end
  end

  @doc "At the end of a run: saves and closes every database it left open."
  def close_all(disk) do
    dbs()
    |> Map.keys()
    |> Enum.map(&close(disk, &1))
    |> Enum.find(:ok, &(&1 != :ok))
  end

  defp write(disk, h, db) do
    with {:ok, bytes} <- serialize(db.conn),
         :ok <- Disk.write(disk, db.path, bytes) do
      Process.put(:dbs, Map.put(dbs(), h, %{db | dirty: false}))
      :ok
    else
      {:error, why} -> {:error, "#{db.path}: not saved: #{why}"}
    end
  end

  # SQLite reads the page count with a pragma to serialize a database it did not load, so the authorizer steps
  # aside for exactly that call
  defp serialize(conn) do
    :ok = Sqlite3.set_authorizer(conn, [])

    try do
      Sqlite3.serialize(conn)
    after
      :ok = Sqlite3.set_authorizer(conn, [:attach, :detach, :pragma])
    end
  end

  defp existing(disk, path) do
    case Disk.read(disk, path) do
      {:ok, bytes} -> {:ok, bytes}
      {:error, :enoent} -> {:ok, ""}
      {:error, why} -> {:error, "#{path}: #{why}"}
    end
  end

  defp load(_conn, ""), do: :ok

  defp load(conn, bytes) do
    if String.starts_with?(bytes, "SQLite format 3\0"),
      do: Sqlite3.deserialize(conn, bytes),
      else: {:error, "not a database"}
  end

  defp fetch(h) do
    case Map.fetch(dbs(), h) do
      {:ok, db} -> {:ok, db}
      :error -> {:error, "the database is closed"}
    end
  end

  defp dbs, do: Process.get(:dbs, %{})

  defp reads?(sql), do: Regex.match?(~r/^\s*(select|values|explain)\b/i, sql)

  # Lua hands numbers as floats; a whole one binds as an integer
  defp param(v) when is_float(v) and v == trunc(v) and abs(v) < 9_007_199_254_740_992,
    do: trunc(v)

  defp param(v), do: v
end

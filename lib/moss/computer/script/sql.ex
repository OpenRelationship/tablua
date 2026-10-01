defmodule Moss.Computer.Script.Sql do
  @moduledoc """
  A script's databases (`db.open("plants.db")` in Lua). A database is named
  by a path on the computer (relative to the working folder, as a file's
  is), shows in `ls`, prints a summary under `cat` and goes with `rm`; it is
  never a file's bytes, and no file is ever opened as one.

  Its SQL is a subset of SQLite's, parsed and run in Elixir (`Moss.Sql.Engine`,
  Arock PROJECT.md §14.7 item 9: no C an agent can reach). While a run has it
  open it lives in the run's memory; each statement's changes (a
  transaction's, at COMMIT) are written to the computer's own file as it ends
  (`Moss.Sql.Store`), so there is nothing to save and a killed run loses only
  the statement it was in. A database is at most #{div(64 * 1024 * 1024, 1_048_576)} MB, a run holds at most
  #{8} open, and each statement's rows count against the run's instruction
  budget.
  """
  alias Moss.Computer.Disk
  alias Moss.Sql.{Budget, Engine, Store}

  @max_open 8

  @doc "Opens the database at `path` (made on its first write) and returns its handle."
  def open(disk, path) do
    dbs = dbs()

    cond do
      map_size(dbs) >= @max_open ->
        {:error, "too many open databases (#{@max_open})"}

      true ->
        with {:ok, db} <- load(disk, path) do
          h = Process.get(:db_next, 1)
          Process.put(:db_next, h + 1)
          Process.put(:dbs, Map.put(dbs, h, %{db: db, path: path}))
          {:ok, h}
        end
    end
  end

  defp load(disk, path) do
    case Store.load(disk.conn, path) do
      {:ok, db} ->
        {:ok, db}

      :none ->
        case Disk.stat(disk, path) do
          {:error, :enoent} ->
            {:ok, Engine.new()}

          {:ok, %{dir: true}} ->
            {:error, "#{path}: is a folder"}

          {:ok, _} ->
            {:error,
             "#{path}: a file, not a database (a database is made by db.open; rm the file first)"}

          {:error, why} ->
            {:error, "#{path}: #{why}"}
        end
    end
  end

  @doc """
  Runs `sql` with `params` with at most `budget` instructions' work:
  `{:ok, rows, changes, spent}` (rows as maps, NULL columns left out) or
  `{:error, why, spent}`.
  """
  def exec(disk, h, sql, params, budget) do
    Budget.start(budget)

    with {:ok, d} <- fetch(h) do
      flush = fn db -> write(disk, d.path, db) end

      case Engine.exec(d.db, sql, params, flush) do
        {:ok, db, r} ->
          Process.put(:dbs, Map.put(dbs(), h, %{d | db: db}))
          {:ok, Enum.map(r.rows, &row(r.names, &1)), r.changes, Budget.spent()}

        {:error, db, why} ->
          Process.put(:dbs, Map.put(dbs(), h, %{d | db: db}))
          {:error, why, Budget.spent()}
      end
    else
      {:error, why} -> {:error, why, 0}
    end
  end

  # a statement's changes to the computer's file; the database's folder made as a file's would be
  defp write(disk, path, db) do
    with :ok <- Disk.mkdir_p(disk, Path.dirname(path)),
         :ok <- Store.flush(disk.conn, path, db) do
      Disk.changed(disk, [path])
    else
      {:error, why} -> {:error, "#{path}: #{why}"}
    end
  end

  defp row(names, values) do
    for {c, v} <- Enum.zip(names, values), v != nil, into: %{}, do: {c, out(v)}
  end

  defp out({:blob, b}), do: b
  defp out(v), do: v

  @doc "Every change is already written: true, unless the database is closed."
  def save(_disk, h), do: with({:ok, _} <- fetch(h), do: :ok)

  @doc "Closes one database; a transaction left open is rolled back, as SQLite's is."
  def close(_disk, h) do
    with {:ok, _} <- fetch(h) do
      Process.put(:dbs, Map.delete(dbs(), h))
      :ok
    end
  end

  @doc "At the end of a run: closes every database it left open."
  def close_all(disk) do
    dbs() |> Map.keys() |> Enum.each(&close(disk, &1))
    :ok
  end

  defp fetch(h) do
    case Map.fetch(dbs(), h) do
      {:ok, d} -> {:ok, d}
      :error -> {:error, "the database is closed"}
    end
  end

  defp dbs, do: Process.get(:dbs, %{})
end

defmodule VolvoxServer.Db do
  @moduledoc """
  The store's db port over Exqlite, as `store/ffi.lua` is on LuaJIT:
  `exec(conn, sql, params)` runs `sql` and returns the rows of its last
  statement as maps with NULL columns left out. Params bind to one statement;
  SQL without params that returns no rows may hold several statements (the
  schema, `begin`, `commit`).
  """
  alias Exqlite.Sqlite3

  @doc "Opens a run's file in WAL mode, so a killed run leaves a log SQLite replays."
  def open(path) do
    with {:ok, conn} <- Sqlite3.open(path),
         :ok <- Sqlite3.execute(conn, "pragma journal_mode = wal; pragma busy_timeout = 5000") do
      {:ok, conn}
    end
  end

  @doc "Folds the WAL into the file and closes it; the file alone is then the run."
  def checkpoint_and_close(conn) do
    with :ok <- Sqlite3.execute(conn, "pragma wal_checkpoint(truncate)"),
         :ok <- Sqlite3.execute(conn, "pragma journal_mode = delete") do
      Sqlite3.close(conn)
    end
  end

  def exec(conn, sql, params) do
    if params == [] and not reads?(sql) do
      with :ok <- Sqlite3.execute(conn, sql), do: {:ok, []}
    else
      query(conn, sql, Enum.map(params, &param/1))
    end
  catch
    kind, reason -> {:error, "sqlite: " <> Exception.format_banner(kind, reason)}
  else
    {:error, reason} -> {:error, to_string(reason)}
    ok -> ok
  end

  defp reads?(sql), do: Regex.match?(~r/^\s*(select|with|pragma|values|explain)\b/i, sql)

  defp query(conn, sql, params) do
    with {:ok, stmt} <- Sqlite3.prepare(conn, sql) do
      try do
        with :ok <- Sqlite3.bind(stmt, params),
             {:ok, cols} <- Sqlite3.columns(conn, stmt),
             {:ok, rows} <- Sqlite3.fetch_all(conn, stmt) do
          {:ok, Enum.map(rows, &row(cols, &1))}
        end
      after
        Sqlite3.release(conn, stmt)
      end
    end
  end

  defp row(cols, values) do
    for {c, v} <- Enum.zip(cols, values), v != nil, into: %{}, do: {c, v}
  end

  # As store/ffi.lua binds: false is NULL, a whole float is an integer.
  defp param(false), do: nil
  defp param(true), do: 1

  defp param(v) when is_float(v) and v == trunc(v) and abs(v) < 9_007_199_254_740_992,
    do: trunc(v)

  defp param(v), do: v
end

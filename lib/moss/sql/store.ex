defmodule Moss.Sql.Store do
  @moduledoc """
  Where an agent's databases are kept: in the computer's own SQLite file, by
  the fixed statements below, every value bound and none written into SQL.
  `sql_dbs` names the databases (by their path on the computer), `sql_schema`
  holds each one's CREATE statements in order, and `sql_rows` its rows,
  keyed by (database, table, rowid), each row encoded here (`encode/1`): a
  byte for the type, then the value. So no SQL an agent writes and no byte it
  stores is read by SQLite as SQL or as a database.
  """
  alias Exqlite.Sqlite3
  alias Moss.Db
  alias Moss.Sql.{Engine, Parser, Schema, Table}

  @setup [
    "create table if not exists sql_dbs (path text primary key, made integer not null, at integer not null)",
    "create table if not exists sql_schema (db text not null, seq integer not null, kind text not null, " <>
      "name text not null, sql text not null, auto integer not null, primary key (db, seq))",
    "create table if not exists sql_rows (db text not null, tbl text not null, rowid integer not null, " <>
      "data blob not null, primary key (db, tbl, rowid)) without rowid"
  ]

  @doc "Makes the tables on a computer's file (`Moss.Computer.Disk.open/2`)."
  def setup(conn) do
    Enum.each(@setup, fn sql -> {:ok, _} = Db.exec(conn, sql, []) end)
    :ok
  end

  def exists?(conn, path),
    do: match?({:ok, [_]}, Db.exec(conn, "select 1 as x from sql_dbs where path = ?1", [path]))

  @doc "A database's entry for `ls` and `stat`: its size (the rows' bytes) and when it last changed."
  def stat(conn, path) do
    case Db.exec(conn, "select at from sql_dbs where path = ?1", [path]) do
      {:ok, [%{"at" => at}]} ->
        {:ok, [row]} =
          Db.exec(
            conn,
            "select coalesce(sum(length(data)), 0) as n from sql_rows where db = ?1",
            [path]
          )

        {:ok, %{dir: false, size: row["n"], mtime: at, db: true}}

      {:ok, []} ->
        nil
    end
  end

  @doc "The databases directly in a folder (`prefix` ends in /)."
  def list(conn, prefix) do
    {:ok, rows} =
      Db.exec(
        conn,
        "select path from sql_dbs where substr(path, 1, length(?1)) = ?1 " <>
          "and instr(substr(path, length(?1) + 1), '/') = 0 order by path",
        [prefix]
      )

    Enum.map(rows, & &1["path"])
  end

  @doc "What `cat` prints for a database: its tables and their rows."
  def describe(conn, path) do
    {:ok, tables} =
      Db.exec(conn, "select name from sql_schema where db = ?1 and kind = 'table' order by seq", [
        path
      ])

    {:ok, counts} =
      Db.exec(conn, "select tbl, count(*) as n from sql_rows where db = ?1 group by tbl", [path])

    counts = Map.new(counts, &{&1["tbl"], &1["n"]})

    lines =
      Enum.map(tables, fn %{"name" => n} ->
        k = String.downcase(n)
        c = Map.get(counts, k, 0)
        "  #{n}: #{c} row#{if c == 1, do: "", else: "s"}\n"
      end)

    "#{Path.basename(path)}: a database (SQL; open it in Lua with db.open), " <>
      "#{length(tables)} table#{if length(tables) == 1, do: "", else: "s"}\n" <> Enum.join(lines)
  end

  def remove(conn, path) do
    with {:ok, _} <- Db.exec(conn, "begin", []),
         {:ok, _} <- Db.exec(conn, "delete from sql_rows where db = ?1", [path]),
         {:ok, _} <- Db.exec(conn, "delete from sql_schema where db = ?1", [path]),
         {:ok, _} <- Db.exec(conn, "delete from sql_dbs where path = ?1", [path]),
         {:ok, _} <- Db.exec(conn, "commit", []) do
      :ok
    else
      e ->
        Db.exec(conn, "rollback", [])
        e
    end
  end

  @doc "A database from the file: `{:ok, db}`, or `:none` when there is none at `path`."
  def load(conn, path) do
    if exists?(conn, path), do: {:ok, read(conn, path)}, else: :none
  end

  defp read(conn, path) do
    {:ok, schema} =
      Db.exec(conn, "select kind, sql, auto from sql_schema where db = ?1 order by seq", [path])

    db =
      Enum.reduce(schema, Engine.new(), fn r, db ->
        {:ok, [{st, _}]} = Parser.parse(r["sql"])

        case st do
          {:create_table, st} ->
            db = Schema.create_table(db, st)
            k = String.downcase(st.name)
            put_in(db.tables[k].seq, r["auto"])

          {:create_index, st} ->
            Schema.create_index(db, st)
        end
      end)

    pads = Map.new(db.tables, fn {k, t} -> {k, Enum.map(t.cols, &Schema.default(&1, ctx()))} end)

    tables =
      rows(conn, path)
      |> Enum.reduce(db.tables, fn {tbl, rowid, data}, tables ->
        case tables do
          %{^tbl => t} -> Map.put(tables, tbl, Table.put(t, rowid, pad(decode(data), pads[tbl])))
          _ -> tables
        end
      end)

    %{db | tables: tables}
  end

  defp ctx,
    do: %{
      db: Engine.new(),
      params: {},
      now: System.os_time(:millisecond),
      changes: 0,
      last_rowid: 0,
      total_changes: 0
    }

  defp rows(conn, path) do
    {:ok, stmt} =
      Sqlite3.prepare(
        conn,
        "select tbl, rowid, data from sql_rows where db = ?1 order by tbl, rowid"
      )

    try do
      :ok = Sqlite3.bind(stmt, [path])
      {:ok, rows} = Sqlite3.fetch_all(conn, stmt)
      Enum.map(rows, fn [tbl, rowid, data] -> {tbl, rowid, data} end)
    after
      Sqlite3.release(conn, stmt)
    end
  end

  # a row stored before ALTER TABLE ADD COLUMN reads the new columns' defaults
  defp pad(vals, defaults) do
    n = length(vals)
    (vals ++ Enum.drop(defaults, n)) |> Enum.take(max(n, length(defaults))) |> List.to_tuple()
  end

  @doc """
  Writes what a statement or a transaction changed, in one transaction of the
  file: the rows (`db.dirty`), the tables dropped, and the schema when it
  changed or a table's AUTOINCREMENT moved.
  """
  def flush(conn, path, db) do
    {:ok, _} = Db.exec(conn, "begin immediate", [])

    try do
      now = System.os_time(:second)

      {:ok, _} =
        Db.exec(
          conn,
          "insert into sql_dbs (path, made, at) values (?1, ?2, ?2) " <>
            "on conflict (path) do update set at = excluded.at",
          [path, now]
        )

      for tbl <- db.dropped,
          do:
            {:ok, _} =
              Db.exec(conn, "delete from sql_rows where db = ?1 and tbl = ?2", [path, tbl])

      autoinc = Enum.any?(db.dirty, fn {k, _} -> match?(%{autoinc: true}, db.tables[k]) end)
      if db.schema or autoinc, do: schema(conn, path, db)
      rows_out(conn, path, db)
      {:ok, _} = Db.exec(conn, "commit", [])
      :ok
    rescue
      e ->
        Db.exec(conn, "rollback", [])
        {:error, "not saved: " <> Exception.message(e)}
    catch
      kind, e ->
        Db.exec(conn, "rollback", [])
        {:error, "not saved: " <> Exception.format_banner(kind, e)}
    end
  end

  defp schema(conn, path, db) do
    {:ok, _} = Db.exec(conn, "delete from sql_schema where db = ?1", [path])

    db.order
    |> Enum.with_index()
    |> Enum.each(fn {{kind, k}, seq} ->
      {name, sql, auto} =
        case kind do
          :table ->
            t = db.tables[k]
            {t.name, t.sql, t.seq}

          :index ->
            ix = Enum.find(db.tables[db.owner[k]].indexes, &(&1.key == k))
            {ix.name, ix.sql, 0}
        end

      {:ok, _} =
        Db.exec(
          conn,
          "insert into sql_schema (db, seq, kind, name, sql, auto) values (?1, ?2, ?3, ?4, ?5, ?6)",
          [path, seq, Atom.to_string(kind), name, sql, auto]
        )
    end)
  end

  defp rows_out(conn, path, db) do
    {:ok, put} =
      Sqlite3.prepare(
        conn,
        "insert or replace into sql_rows (db, tbl, rowid, data) values (?1, ?2, ?3, ?4)"
      )

    {:ok, del} =
      Sqlite3.prepare(conn, "delete from sql_rows where db = ?1 and tbl = ?2 and rowid = ?3")

    try do
      Enum.each(db.dirty, fn {tbl, rowid} ->
        case db.tables[tbl] && Table.get(db.tables[tbl], rowid) do
          nil -> step(conn, del, [path, tbl, rowid])
          row -> step(conn, put, [path, tbl, rowid, {:blob, encode(row)}])
        end
      end)
    after
      Sqlite3.release(conn, put)
      Sqlite3.release(conn, del)
    end
  end

  defp step(conn, stmt, args) do
    :ok = Sqlite3.bind(stmt, args)
    :done = Sqlite3.step(conn, stmt)
    :ok = Sqlite3.reset(stmt)
  end

  # -- the row encoding: only this code writes it and only this code reads it ----------------------

  @doc "A row (a tuple of values) as bytes: per value a tag (0 NULL, 1 integer, 2 real, 3 text, 4 blob)."
  def encode(row) do
    row
    |> Tuple.to_list()
    |> Enum.map(fn
      nil -> <<0>>
      i when is_integer(i) -> <<1, i::signed-64>>
      f when is_float(f) -> <<2, f::float-64>>
      s when is_binary(s) -> <<3, byte_size(s)::32, s::binary>>
      {:blob, b} -> <<4, byte_size(b)::32, b::binary>>
    end)
    |> IO.iodata_to_binary()
  end

  def decode(<<>>), do: []
  def decode(<<0, rest::binary>>), do: [nil | decode(rest)]
  def decode(<<1, i::signed-64, rest::binary>>), do: [i | decode(rest)]
  def decode(<<2, f::float-64, rest::binary>>), do: [f | decode(rest)]
  def decode(<<3, n::32, s::binary-size(n), rest::binary>>), do: [s | decode(rest)]
  def decode(<<4, n::32, b::binary-size(n), rest::binary>>), do: [{:blob, b} | decode(rest)]
end

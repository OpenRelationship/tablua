defmodule Moss.Sql.BenchTest do
  # What the agent's database costs (Arock PROJECT.md §14.7 item 9), against the exqlite path it replaced: an
  # in-memory SQLite the agent's SQL ran on, serialized whole and written into the computer's file when the
  # run saved it. The new path is Moss.Sql.Engine with each statement's rows written to the computer's file
  # as it ends (Moss.Sql.Store). Not a pass/fail check: `mix test --only bench` prints the table.
  use ExUnit.Case, async: false

  alias Exqlite.Sqlite3
  alias Moss.Db
  alias Moss.Sql.{Engine, Store}

  @moduletag :bench
  @n 10_000

  defp file do
    path = Path.join(System.tmp_dir!(), "moss-bench-#{System.unique_integer([:positive])}.sqlite")
    {:ok, conn} = Db.open(path)
    on_exit(fn -> Enum.each(["", "-wal", "-shm"], &File.rm(path <> &1)) end)
    conn
  end

  defp ms(f) do
    {us, v} = :timer.tc(f)
    {Float.round(us / 1000, 1), v}
  end

  # -- the new path ------------------------------------------------------------------------------

  defp new_db do
    conn = file()
    :ok = Store.setup(conn)
    flush = fn db -> Store.flush(conn, "/home/bench.db", db) end
    flush
  end

  defp ex(db, flush, sql, params \\ []) do
    {:ok, db, r} = Engine.exec(db, sql, params, flush)
    {db, r}
  end

  defp new_insert(tx) do
    flush = new_db()

    {db, _} =
      ex(Engine.new(), flush, "create table t (id integer primary key, k int, g text, v real)")

    {db, _} = ex(db, flush, "create index t_k on t (k)")
    db = if tx, do: elem(ex(db, flush, "begin"), 0), else: db

    db =
      Enum.reduce(1..@n, db, fn i, db ->
        elem(
          ex(db, flush, "insert into t (k, g, v) values (?, ?, ?)", [
            i * 7,
            "g#{rem(i, 20)}",
            i / 3
          ]),
          0
        )
      end)

    db = if tx, do: elem(ex(db, flush, "commit"), 0), else: db
    {db, flush}
  end

  # -- the old path ------------------------------------------------------------------------------

  defp old_exec(conn, sql, params) do
    {:ok, st} = Sqlite3.prepare(conn, sql)
    :ok = Sqlite3.bind(st, params)
    {:ok, rows} = Sqlite3.fetch_all(conn, st)
    Sqlite3.release(conn, st)
    rows
  end

  defp old_save(conn, disk) do
    {:ok, bytes} = Sqlite3.serialize(conn)

    {:ok, _} =
      Db.exec(disk, "insert or replace into f (path, bytes) values (?1, ?2)", [
        "/home/bench.db",
        bytes
      ])
  end

  defp old_insert(tx) do
    disk = file()
    {:ok, _} = Db.exec(disk, "create table f (path text primary key, bytes blob)", [])
    {:ok, conn} = Sqlite3.open(":memory:")
    old_exec(conn, "create table t (id integer primary key, k int, g text, v real)", [])
    old_exec(conn, "create index t_k on t (k)", [])
    if tx, do: old_exec(conn, "begin", [])

    Enum.each(1..@n, fn i ->
      old_exec(conn, "insert into t (k, g, v) values (?, ?, ?)", [i * 7, "g#{rem(i, 20)}", i / 3])
    end)

    if tx, do: old_exec(conn, "commit", [])
    old_save(conn, disk)
    conn
  end

  test "10k inserts, 1000 indexed selects and a group-by over 10k rows: the Elixir engine against exqlite" do
    {new_auto, _} = ms(fn -> new_insert(false) end)
    {new_tx, {db, flush}} = ms(fn -> new_insert(true) end)
    {old_auto, _} = ms(fn -> old_insert(false) end)
    {old_tx, conn} = ms(fn -> old_insert(true) end)

    keys = for i <- 1..1000, do: rem(i * 7919, @n) * 7 + 7

    {new_sel, rows} =
      ms(fn ->
        Enum.map(keys, &elem(ex(db, flush, "select id, g from t where k = ?", [&1]), 1).rows)
      end)

    {old_sel, rows2} =
      ms(fn -> Enum.map(keys, &old_exec(conn, "select id, g from t where k = ?", [&1])) end)

    assert rows == rows2

    group = "select g, count(*), sum(k), avg(v) from t group by g order by g"
    {new_grp, %{rows: g1}} = ms(fn -> elem(ex(db, flush, group), 1) end)
    {old_grp, g2} = ms(fn -> old_exec(conn, group, []) end)
    assert g1 == g2

    IO.puts("""

    agent database, ms (Elixir engine + per-statement write  vs  exqlite in memory + one save)
      10k inserts, autocommit      #{new_auto}  vs  #{old_auto}
      10k inserts, one transaction #{new_tx}  vs  #{old_tx}
      1000 indexed point selects   #{new_sel}  vs  #{old_sel}
      group-by over 10k rows       #{new_grp}  vs  #{old_grp}
    """)
  end
end

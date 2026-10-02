defmodule Moss.Sql.EngineTest do
  # Moss.Sql.Engine on its own (Arock PROJECT.md §14.7 item 9): what it refuses by name, its limits, its
  # parameters, statement atomicity, and when it hands rows to the file. The answers themselves are checked
  # against real SQLite in the diff_* suites.
  use ExUnit.Case, async: true

  alias Moss.Sql.{Engine, Lexer, Store}

  defp ok(db, sql, params \\ []) do
    {:ok, db, r} = Engine.exec(db, sql, params, fn _ -> :ok end)
    {db, r}
  end

  defp err(db, sql, params \\ []) do
    {:error, _db, why} = Engine.exec(db, sql, params, fn _ -> :ok end)
    why
  end

  test "statements outside the subset are refused by name, never passed on" do
    db = Engine.new()
    {db, _} = ok(db, "create table t (a)")

    for {sql, named} <- [
          {"pragma table_info(t)", "PRAGMA"},
          {"attach 'x.db' as x", "ATTACH"},
          {"detach x", "DETACH"},
          {"vacuum", "VACUUM"},
          {"analyze", "ANALYZE"},
          {"savepoint s", "SAVEPOINT"},
          {"explain select 1", "EXPLAIN"},
          {"with c as (select 1) select * from c", "WITH"},
          {"create view v as select 1", "CREATE VIEW"},
          {"create trigger g after insert on t begin select 1; end", "CREATE TRIGGER"},
          {"create virtual table f using fts5(a)", "CREATE VIRTUAL TABLE"},
          {"create table w (a primary key) without rowid", "WITHOUT ROWID"},
          {"create table s (a int) strict", "STRICT"},
          {"create index i on t (a) where a > 0", "a partial index"},
          {"create index i on t (a + 1)", "an index on an expression"},
          {"alter table t rename to u", "RENAME"},
          {"alter table t drop column a", "DROP COLUMN"},
          {"select a, row_number() over () from t", "OVER"},
          {"select * from t natural join t", "NATURAL JOIN"},
          {"select * from t right join t u", "RIGHT JOIN"},
          {"select * from x.t", "another database"},
          {"select * from t indexed by i", "INDEXED BY"},
          {"update t set a = 1 from t u", "UPDATE ... FROM"},
          {"select * from json_each('[1]')", "table-valued function"}
        ] do
      why = err(db, sql)
      assert why =~ named, "#{sql}: #{why}"

      assert why =~ "is not supported (the database speaks a subset of SQLite: help data)",
             "#{sql}: #{why}"
    end
  end

  test "a statement is at most 1 MB and an expression 1000 high" do
    db = Engine.new()

    assert err(db, "select '" <> String.duplicate("x", 1_048_576) <> "'") =~
             "a statement is at most 1024 KB"

    assert err(db, "select 1" <> String.duplicate("+1", 1000)) =~ "maximum depth 1000"

    assert {_, %{rows: [[1]]}} =
             ok(
               db,
               "select " <> String.duplicate("(", 1500) <> "1" <> String.duplicate(")", 1500)
             )
  end

  test "parameters: ?, ?N and :name, counted, and only plain values" do
    db = Engine.new()
    assert {_, %{rows: [[1, "b", 1]]}} = ok(db, "select ?, ?2, ?1", [1, "b"])
    assert {_, %{rows: [[3, 3]]}} = ok(db, "select :x, :x + 0", [3])
    assert err(db, "select ?, ?", [1]) =~ "parameter"
    assert err(db, "select ?", [1, 2]) =~ "parameter"
  end

  test "a database is at most 64 MB" do
    db = Engine.new()
    {db, _} = ok(db, "create table t (a)")
    big = String.duplicate("x", 15 * 1024 * 1024)
    db = Enum.reduce(1..4, db, fn _, db -> elem(ok(db, "insert into t values (?)", [big]), 0) end)
    assert err(db, "insert into t values (?)", [big]) == "database or disk is full"
    assert {_, %{rows: [[4]]}} = ok(db, "select count(*) from t")
  end

  test "a statement that fails leaves nothing behind" do
    db = Engine.new()
    {db, _} = ok(db, "create table t (a unique)")
    assert err(db, "insert into t values (1), (2), (1)") == "UNIQUE constraint failed: t.a"
    assert {_, %{rows: [[0]]}} = ok(db, "select count(*) from t")
    {db, _} = ok(db, "insert into t values (1), (2)")
    assert err(db, "update t set a = 5") == "UNIQUE constraint failed: t.a"
    assert {_, %{rows: [[1], [2]]}} = ok(db, "select a from t order by a")
  end

  test "rows go to the file as each statement ends, or once at COMMIT, and never after ROLLBACK" do
    me = self()

    flush = fn db ->
      send(me, {:flush, Engine.summary(db)})
      :ok
    end

    run = fn db, sql ->
      {:ok, db, _} = Engine.exec(db, sql, [], flush)
      db
    end

    db =
      Engine.new()
      |> run.("create table t (a)")
      |> run.("insert into t values (1)")
      |> run.("select * from t")

    assert flushes() == 2

    db = run.(db, "begin; insert into t values (2); insert into t values (3)")
    assert flushes() == 0
    db = run.(db, "commit")
    assert flushes() == 1

    db = run.(db, "begin; insert into t values (4); rollback")
    assert flushes() == 0

    failing = fn _ -> {:error, "disk I/O error"} end

    assert {:error, db, "disk I/O error"} =
             Engine.exec(db, "insert into t values (5)", [], failing)

    assert {:ok, _, %{rows: [[1], [2], [3]]}} =
             Engine.exec(db, "select a from t order by a", [], flush)
  end

  defp flushes(n \\ 0) do
    receive do
      {:flush, _} -> flushes(n + 1)
    after
      0 -> n
    end
  end

  test "rows are kept in a tagged encoding of their own, read back exactly" do
    rows = [
      [nil, 0, -1, 9_223_372_036_854_775_807, -9_223_372_036_854_775_808],
      [
        0.0,
        -0.0,
        1.5e300,
        5.0e-324,
        "",
        "text with \0 and é",
        {:blob, <<>>},
        {:blob, <<0, 255, 1>>}
      ]
    ]

    for row <- rows do
      bin = Store.encode(List.to_tuple(row))
      assert is_binary(bin)
      assert Store.decode(bin) === row
    end

    refute Store.encode({"x"}) == :erlang.term_to_binary("x")
  end

  test "the lexer: quoting, numbers, blobs, parameters and comments" do
    {:ok, ts} =
      Lexer.tokens(
        "SELECT \"a b\", [c], `d`, 'it''s', 0x1F, 1.5e3, x'00ff', ?, ?2, :n, @m, $o -- note\n/* c */;"
      )

    kinds = Enum.map(ts, &elem(&1, 0))

    assert kinds == [
             :word,
             :id,
             :op,
             :id,
             :op,
             :id,
             :op,
             :str,
             :op,
             :num,
             :op,
             :num,
             :op,
             :blob,
             :op,
             :param,
             :op,
             :param,
             :op,
             :param,
             :op,
             :param,
             :op,
             :param,
             :semi
           ]

    assert Enum.find(ts, &(elem(&1, 0) == :str)) |> elem(1) == "it's"
    assert {:error, _} = Lexer.tokens("select 'open")
  end
end

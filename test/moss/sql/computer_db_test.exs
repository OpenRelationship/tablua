defmodule Moss.Sql.ComputerDbTest do
  # The agent's database on its computer (Arock PROJECT.md §14.7 item 9): named inside the computer, never a
  # file's bytes; its SQL run in Elixir, its rows in the computer's own file by fixed statements; its work on
  # the run's budget. And the proof: no SQL an agent writes is ever handed to SQLite.
  use ExUnit.Case, async: false

  alias Moss.Computer
  alias Moss.Computer.Disk

  defp id, do: "sqldb-#{System.unique_integer([:positive])}"
  defp sh(c, line), do: Computer.run(c, line)

  defp put(c, path, text),
    do: :ok = Disk.write(:sys.get_state(Computer.wake!(c)).disk, path, text)

  defp lua(c, code), do: sh(c, "lua -e '#{code}'")

  test "a database is an entry: ls and stat show it, cat sums it up, rm removes it, nothing writes over it" do
    c = id()

    assert %{code: 0} =
             lua(
               c,
               ~S|local d = db.open("data/p.dbl") d:exec("create table t (a)") d:exec("insert into t values (1), (2)")|
             )

    assert %{out: "data/\norg/\n"} = sh(c, "ls")
    assert %{out: "p.dbl\n"} = sh(c, "ls data")
    assert %{out: "- " <> _} = sh(c, "ls -l data")

    assert %{out: "true\tfalse\n"} =
             lua(c, ~S|print(fs.exists("data/p.dbl"), fs.isdir("data/p.dbl"))|)

    assert %{out: "p.dbl: a database (SQL; open it in Lua with db.open), 1 table\n  t: 2 rows\n"} =
             sh(c, "cat data/p.dbl")

    # data/ holds databases only, so a file's bytes are refused there before they meet one
    in_data =
      "a database goes in data/ as .dbl, opened with db.open; a file's bytes never become one"

    database = "is a database (change it with SQL through db.open in Lua; rm removes it)"
    assert %{out: out} = lua(c, ~S|print(fs.write("data/p.dbl", "x"))|)
    assert out == "nil\t#{in_data}\n"
    assert %{code: 1, err: "cp: /home/data/p.dbl: " <> _} = sh(c, "cp data/p.dbl data/q.dbl")
    put(c, "/home/files/f.txt", "hello")
    assert %{code: 1, err: err} = sh(c, "cp files/f.txt data/p.dbl")
    assert err =~ in_data

    assert %{code: 1, err: "mv: /home/files/f.txt: " <> ^database <> "\n"} =
             sh(c, "mv files/f.txt data/p.dbl")

    assert %{code: 1, err: "mv: /home/data/p.dbl: " <> ^database <> "\n"} =
             sh(c, "mv data/p.dbl data/r.dbl")

    assert %{code: 1} = sh(c, "mkdir data/p.dbl")

    assert %{out: "2\n"} =
             lua(c, ~S|print(db.open("data/p.dbl"):one("select count(*) as n from t").n)|)

    assert %{code: 0} = sh(c, "rm data/p.dbl")
    assert %{out: ""} = sh(c, "ls data")
    assert %{out: "f.txt\n"} = sh(c, "ls files")

    assert %{out: "nil\tno such table: t\n"} =
             lua(c, ~S|print(db.open("data/p.dbl"):query("select * from t"))|)
  end

  test "databases sit in folders by path, and a database's folder is made as a file's would be" do
    c = id()
    assert %{code: 0} = lua(c, ~S|db.open("/home/data/x/a.dbl"):exec("create table t (a)")|)
    assert %{code: 0} = lua(c, ~S|db.open("/home/data/b.dbl"):exec("create table t (a)")|)
    assert %{out: "b.dbl\nx/\n"} = sh(c, "ls /home/data")
    assert %{out: "a.dbl\n"} = sh(c, "ls /home/data/x")
    assert %{out: "/home/data/x/a.dbl\n"} = sh(c, "find /home/data -name a.dbl")
  end

  test "values keep their types between runs; ALTER, AUTOINCREMENT and indexes survive; ROLLBACK leaves nothing" do
    c = id()

    put(c, "/home/code/w.lua", ~S"""
    local d = db.open("data/v.dbl")
    d:exec([[create table t (id integer primary key autoincrement, i int, r real, s text, b blob, n)]])
    d:exec("create index t_s on t (s)")
    d:exec("insert into t (i, r, s, b, n) values (?, ?, ?, x'0001ff', ?)", 7, 1.5, "seven", nil)
    d:exec("insert into t (i, r, s) values (8, 2, 'eight')")
    d:exec("delete from t where i = 8")
    d:exec("alter table t add column extra text default 'x'")
    d:exec("begin")
    d:exec("insert into t (i) values (99)")
    d:exec("rollback")
    d:exec("begin; insert into t (i) values (100); commit")
    """)

    assert %{code: 0, err: ""} = sh(c, "lua code/w.lua")

    assert %{out: out} =
             lua(
               c,
               ~S|local d = db.open("data/v.dbl") for _, r in ipairs(d:query("select id, typeof(i) ti, typeof(r) tr, typeof(s) ts, typeof(b) tb, typeof(n) tn, extra, length(b) lb from t order by id")) do print(r.id, r.ti, r.tr, r.ts, r.tb, r.tn, r.extra, r.lb) end print(d:one("select max(id) m from t").m)|
             )

    assert out ==
             "1\tinteger\treal\ttext\tblob\tnull\tx\t3\n3\tinteger\tnull\tnull\tnull\tnull\tx\tnil\n3\n"

    assert %{out: "1\n"} =
             lua(
               c,
               ~S|print(#db.open("data/v.dbl"):query("select * from t where s = ?", "seven"))|
             )

    assert %{out: "4\n"} =
             lua(
               c,
               ~S|local d = db.open("data/v.dbl") d:exec("insert into t (i) values (1)") print(d:one("select max(id) m from t").m)|
             )
  end

  test "a statement's work is spent from the run's instruction budget: a huge join ends instead of hanging the computer" do
    c = id()
    prev = Application.get_env(:moss, :script_instructions)
    Application.put_env(:moss, :script_instructions, 5_000_000)

    try do
      assert %{code: 0} =
               lua(
                 c,
                 ~S|local d = db.open("data/big.dbl") d:exec("create table t (a)") local v = {} for i = 1, 400 do v[#v + 1] = "(" .. i .. ")" end d:exec("insert into t values " .. table.concat(v, ","))|
               )

      # a join that keeps nothing costs only time, and the budget ends it
      {us, r} =
        :timer.tc(fn ->
          lua(
            c,
            ~S|print(db.open("data/big.dbl"):query("select count(*) n from t a, t b, t c where a.a + b.a + c.a < 0"))|
          )
        end)

      assert r.out == "nil\tinterrupted: the statement ran past the run's instruction budget\n"
      assert us < 10_000_000

      # one that keeps every row ends on the run's memory, as a Lua table that big would
      assert %{code: 137, err: "lua: out of memory" <> _} =
               lua(
                 c,
                 ~S|print(db.open("data/big.dbl"):query("select a.a, b.a, c.a from t a, t b, t c"))|
               )

      assert %{out: "400\n"} =
               lua(c, ~S|print(db.open("data/big.dbl"):one("select count(*) n from t").n)|)
    after
      if prev,
        do: Application.put_env(:moss, :script_instructions, prev),
        else: Application.delete_env(:moss, :script_instructions)
    end
  end

  test "a run holds at most 8 databases; a statement is at most 1 MB and an expression 1000 high" do
    c = id()

    assert %{out: out} =
             lua(
               c,
               ~S|for i = 1, 9 do local d, why = db.open("data/d" .. i .. ".dbl") if not d then print(i, why) end end|
             )

    assert out == "9\ttoo many open databases (8)\n"

    # a helper that opens its database on every call (a budget run's steps did, 9 times) keeps one handle
    assert %{out: "20\n"} =
             lua(
               c,
               ~S|local d for i = 1, 20 do d = db.open("data/one.dbl") d:exec("create table if not exists t (n)") d:exec("insert into t values (?)", i) end print(d:one("select count(*) n from t").n)|
             )

    assert %{out: "nil\tstring or blob too big: a statement is at most 1024 KB\n"} =
             lua(
               c,
               ~S|print(db.open("data/a.dbl"):query("select " .. string.rep("1+", 600000) .. "1"))|
             )

    assert %{out: "nil\tExpression tree is too large (maximum depth 1000)\n"} =
             lua(
               c,
               ~S|print(db.open("data/a.dbl"):query("select " .. "1" .. string.rep("+1", 1000)))|
             )
  end

  test "no SQL an agent writes, and no database bytes, ever reach SQLite" do
    c = id()
    marker = "agent_marker_#{System.unique_integer([:positive])}"
    Computer.wake!(c)

    script = """
    local d = db.open("data/m.dbl")
    d:exec("create table #{marker} (k text primary key, v)")
    d:exec("create index #{marker}_v on #{marker} (v)")
    d:exec("insert into #{marker} values ('#{marker}', 1), ('b', 2) on conflict do nothing")
    d:exec("update #{marker} set v = v + 1 where k like '#{marker}%'")
    print(#d:query("select * from #{marker} where v > 0 order by k"))
    d:exec("begin; delete from #{marker} where k = 'b'; commit")
    """

    put(c, "/home/code/m.lua", script)
    :erlang.trace_pattern({Exqlite.Sqlite3NIF, :_, :_}, true, [:local])
    :erlang.trace(:all, true, [:call])

    try do
      assert %{code: 0, out: "2\n"} = sh(c, "lua code/m.lua")
    after
      :erlang.trace(:all, false, [:call])
      :erlang.trace_pattern({Exqlite.Sqlite3NIF, :_, :_}, false, [:local])
    end

    calls = drain([])
    sql = for {f, [_conn, text | _]} <- calls, f in [:prepare, :execute], do: text
    assert sql != [], "the trace saw no SQLite calls at all"
    assert Enum.all?(sql, &is_binary/1)

    refute Enum.any?(sql, &String.contains?(&1, marker)),
           "agent SQL reached SQLite: #{inspect(Enum.filter(sql, &String.contains?(&1, marker)))}"

    refute Enum.any?(calls, fn {f, _} -> f in [:deserialize, :serialize] end)

    assert Enum.all?(
             sql,
             &(&1 =~
                 ~r/sql_(dbs|schema|rows)|^(begin|commit|rollback|savepoint|release)|events|files|kept|nodes|pragma|select|insert|update|delete|create/i)
           )
  end

  defp drain(acc) do
    receive do
      {:trace, _pid, :call, {Exqlite.Sqlite3NIF, f, args}} -> drain([{f, args} | acc])
    after
      200 -> Enum.reverse(acc)
    end
  end
end

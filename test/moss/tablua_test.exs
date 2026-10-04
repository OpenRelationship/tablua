defmodule Moss.TabluaTest do
  # The harness's own tables (core/tablua): only statements over tablua_ tables pass the door.
  use ExUnit.Case, async: true

  alias Moss.Computer.Tablua

  test "the harness's statements over its own tables pass" do
    for s <- [
          "create table if not exists tablua_x (a text); create table if not exists tablua_y (b text)",
          "insert or replace into tablua_state (task, n) values (?, ?)",
          "select s.n from main.tablua_state s join main.tablua_decision d on d.n = s.n left join shared.tablua_run r on 1",
          "select count(*) as n from tablua_outcome",
          "create view if not exists tablua_break as select file from tablua_link l where not exists " <>
            "(select 1 from tablua_unit u where u.name = l.target)"
        ],
        do: assert(Tablua.allowed(s, []) == :ok, s)
  end

  test "anything else is refused, naming why" do
    assert {:error, "tablua: refused (names a table that is not tablua_)" <> _} =
             Tablua.allowed("select * from events", [])

    assert {:error, _} = Tablua.allowed("select 1 from tablua_state; delete from args", [])
    assert {:error, _} = Tablua.allowed("create view if not exists tablua_v as select * from events", [])
    assert {:error, _} = Tablua.allowed("create view if not exists v as select * from tablua_state", [])
    assert {:error, "tablua: refused (not a statement the harness makes)" <> _} = Tablua.allowed("drop table tablua_state", [])
    assert {:error, "tablua: refused (attach only the shared experience)" <> _} =
             Tablua.allowed("attach database ? as x", ["/etc/passwd"])
  end
end

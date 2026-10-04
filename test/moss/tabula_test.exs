defmodule Moss.TabulaTest do
  # The harness's own tables (library/tabula): only statements over tabula_ tables pass the door.
  use ExUnit.Case, async: true

  alias Moss.Computer.Tabula

  test "the harness's statements over its own tables pass" do
    for s <- [
          "create table if not exists tabula_x (a text); create table if not exists tabula_y (b text)",
          "insert or replace into tabula_state (task, n) values (?, ?)",
          "select s.n from main.tabula_state s join main.tabula_decision d on d.n = s.n left join shared.tabula_run r on 1",
          "select count(*) as n from tabula_outcome"
        ],
        do: assert(Tabula.allowed(s, []) == :ok, s)
  end

  test "anything else is refused, naming why" do
    assert {:error, "tabula: refused (names a table that is not tabula_)" <> _} =
             Tabula.allowed("select * from events", [])

    assert {:error, _} = Tabula.allowed("select 1 from tabula_state; delete from args", [])
    assert {:error, "tabula: refused (not a statement the harness makes)" <> _} = Tabula.allowed("drop table tabula_state", [])
    assert {:error, "tabula: refused (attach only the shared experience)" <> _} =
             Tabula.allowed("attach database ? as x", ["/etc/passwd"])
  end
end

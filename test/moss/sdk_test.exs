defmodule Moss.SdkTest do
  # The Lua SDK agents build with (Arock PROJECT.md §14.7, goal 4): a database per computer, CSV, dates, HTML
  # Markdown, and Gherkin features run by Lua steps as Robot rows, on top of fs, http, json and mail.
  use ExUnit.Case, async: false

  alias Moss.Computer
  alias Moss.Computer.Disk

  defp id, do: "sdk-#{System.unique_integer([:positive])}"
  defp sh(id, line), do: Computer.run(id, line)
  defp disk(c), do: :sys.get_state(Computer.wake!(c)).disk
  defp put(c, path, text), do: :ok = Disk.write(disk(c), path, text)

  test "a database is named on the computer, kept between runs, and shown by ls and cat" do
    c = id()

    put(c, "/home/code/add.lua", ~S"""
    local d = assert(db.open("data/plants.dbl"))
    d:exec("create table if not exists plant (name text primary key, water int, note text)")
    print(d:exec("insert into plant values (?, ?, ?)", arg[1], tonumber(arg[2]), nil))
    """)

    assert %{code: 0, out: "1\n"} = sh(c, "lua code/add.lua fern 3")
    assert %{code: 0, out: "1\n"} = sh(c, "lua code/add.lua moss 1")

    # left open, still saved when the run ends
    assert %{code: 0} =
             sh(
               c,
               ~s|lua -e 'db.open("data/plants.dbl"):exec("update plant set water = water + 1")'|
             )

    assert %{code: 0, out: "fern\t4\tnil\nmoss\t2\tnil\nmoss\n"} =
             sh(
               c,
               ~s|lua -e 'local d = db.open("data/plants.dbl") for _, r in ipairs(d:query("select * from plant order by name")) do print(r.name, r.water, r.note) end print(d:one("select name from plant where water < ?", 3).name) d:close()'|
             )

    assert %{
             code: 0,
             out:
               "plants.dbl: a database (SQL; open it in Lua with db.open), 1 table\n  plant: 2 rows\n"
           } =
             sh(c, "cat data/plants.dbl")

    assert %{code: 0, out: "code/\ndata/\n"} = sh(c, "ls")
    assert %{code: 0, out: "plants.dbl\n"} = sh(c, "ls data")
  end

  test "a database reaches no other database, no file, and no SQL beyond its own" do
    c = id()

    put(c, "/home/code/x.lua", ~S"""
    local d = db.open("data/x.dbl")
    print(d:exec("attach '/tmp/y.db' as y"))
    print(d:exec("pragma max_page_count = 1000000000"))
    print(d:exec("vacuum into '/tmp/z.db'"))
    print(d:exec("create view v as select 1"))
    print(d:query("with t as (select 1) select * from t"))
    print(d:query("select nope"))
    """)

    assert %{code: 0, out: out} = sh(c, "lua code/x.lua")
    assert [a, p, v, cv, w, q] = String.split(out, "\n", trim: true)
    assert a == "nil\tATTACH is not supported (the database speaks a subset of SQLite: help lua)"
    assert p =~ ~r/^nil\tPRAGMA is not supported/
    assert v =~ ~r/^nil\tVACUUM is not supported/
    assert cv =~ ~r/^nil\tCREATE VIEW is not supported/
    assert w =~ ~r/^nil\tWITH \(a common table expression\) is not supported/
    assert q == "nil\tno such column: nope"

    # a file's bytes are never a database, whatever they hold: none is written in data/, none opened elsewhere
    assert {:error, "a database goes in data/ as .dbl" <> _} =
             Disk.write(disk(c), "/home/data/bad.dbl", "SQLite format 3\0 or anything else")

    put(c, "/home/files/bad.dbl", "SQLite format 3\0 or anything else")

    assert %{out: "nil\ta database goes in data/ as .dbl" <> _} =
             sh(c, ~s|lua -e 'print(db.open("files/bad.dbl"))'|)
  end

  test "csv and date read and write what agents meet" do
    c = id()

    put(
      c,
      "/home/files/t.csv",
      "name,note\nfern,\"likes \"\"shade\"\", damp\"\nmoss,\"two\nlines\"\n"
    )

    put(c, "/home/code/c.lua", ~S"""
    local csv, date = require("csv"), require("date")
    local rows, names = csv.parse(fs.read("files/t.csv"), { header = true })
    print(#rows, names[2], rows[1].note, rows[2].note == "two\nlines")
    io.write(csv.encode(rows, { "name", "note" }))
    local t = date.parse("2024-02-29T23:30:00Z")
    print(date.iso(t), date.day(date.add(t, { years = 1 })), date.day(date.add(t, { days = 1 })))
    print(date.format(t, "%A %d %B %Y, day %j"), date.diff(date.parse("2026-10-01"), date.parse("2026-09-01"), "days"))
    print(date.iso(date.parse("2026-10-01T09:00:00+02:00")), date.parts(0).weekday)
    """)

    assert %{code: 0, out: out} = sh(c, "lua code/c.lua")

    assert out ==
             """
             2\tnote\tlikes "shade", damp\ttrue
             name,note
             fern,"likes ""shade"", damp"
             moss,"two
             lines"
             2024-02-29T23:30:00Z\t2025-02-28\t2024-03-01
             Thursday 29 February 2024, day 060\t30
             2026-10-01T07:00:00Z\t4
             """
  end

  test "Shroomi builds pages on the computer: components, utilities, templates and markdown" do
    c = id()

    put(c, "/home/code/h.lua", ~S"""
    local ui = require("shroomi")
    ui.component("plant", function(p) return ui.li{ class = "flex gap-2", p.name } end)
    local page = ui.page{ title = "Plants",
      ui.card{ title = "<Ferns & co>", ui.ul{ ui.plant{ name = "fern" } }, ui.markdown("**dry** <b>") } }
    print(string.match(page, "<body.-</body>"))
    print(string.find(page, ".gap-2{", 1, true) ~= nil, ui.escape("<i>"))
    print(table.concat(ui.check('<p class="p-4 wobbly">'), ","))
    """)

    assert %{code: 0, out: out} = sh(c, "lua code/h.lua")

    assert out ==
             ~s(<body class="min-h-screen bg-background text-foreground"><div class="card"><header><h2>&lt;Ferns &amp; co&gt;</h2></header>) <>
               ~s(<section><ul><li class="flex gap-2">fern</li></ul><div class="prose"><p><strong>dry</strong> &lt;b&gt;</p>\n</div>) <>
               ~s(</section></div></body>\ntrue\t&lt;i&gt;\nwobbly\n)
  end

  test "a Gherkin feature runs on Lua steps and prints Robot rows" do
    c = id()

    put(c, "/home/features/sum.feature", ~S'''
    Feature: Sums
      Background:
        Given a sum starting at 1

      Scenario: adding
        When I add 2
        Then the sum is 3

      Scenario Outline: adding <n>
        When I add <n>
        Then the sum is <total>
        Examples:
          | n | total |
          | 4 | 5     |
          | 5 | 7     |

      Scenario: a note
        Given the note
          """
          two words
          """
        Then nothing matches this
        And the sum is 1
    ''')

    put(c, "/home/code/steps.lua", ~S"""
    local test = require("test")
    test.step("a sum starting at {int}", function(w, n) w.sum = n end)
    test.step("I add {int}", function(w, n) w.sum = w.sum + n end)
    test.step("the sum is {int}", function(w, n) test.eq(w.sum, n, "sum") end)
    test.step("the note", function(w, doc) test.eq(doc, "two words") end)
    local ok = test.run_file("features/sum.feature")
    os.exit(ok and 0 or 1)
    """)

    assert %{code: 1, out: out} = sh(c, "lua code/steps.lua")

    assert out ==
             """
             *** Test Cases ***
             adding
                 Given a sum starting at 1    PASS
                 When I add 2    PASS
                 Then the sum is 3    PASS
             adding 4 (4, 5)
                 Given a sum starting at 1    PASS
                 When I add 4    PASS
                 Then the sum is 5    PASS
             adding 5 (5, 7)
                 Given a sum starting at 1    PASS
                 When I add 5    PASS
                 Then the sum is 7    FAIL    code/steps.lua:4: sum: wanted 7, got 6
             a note
                 Given a sum starting at 1    PASS
                 Given the note    PASS
                 Then nothing matches this    FAIL    no step matches: nothing matches this
                 And the sum is 1    NOT RUN
             # no step matches "nothing matches this"; paste this into code/steps/ and write it:
             test.step("nothing matches this", function(w)
               error("not written yet")
             end)
             # Sums: 2 of 4 scenarios passed
             """
  end
end

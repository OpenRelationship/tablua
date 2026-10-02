defmodule Moss.AgentToolTest do
  # Goal 4's proof (Arock PROJECT.md §14.7): a model, given only its own computer, learns the Lua SDK from `help lua`,
  # specifies a small tool in Gherkin, builds it to green on its own computer, and the tool then does what was asked
  # when this test drives it. Live: it calls Mercury (Moss.AgentLoop) with the host's key, which never reaches the
  # computer. Run with `mix test --only agent`.
  use ExUnit.Case, async: false

  alias Moss.Computer

  @moduletag :agent
  @moduletag timeout: 3_600_000

  setup_all do
    Moss.AgentLoop.own_folders()
    :ok
  end

  @task """
  You have your own computer, reached through the `computer` tool. It is not Linux: its commands are few (run
  `help`), and its one language is Lua (run `help lua` for the library, which is all a script can use).

  Build a small tool there, in /home/plants:

    lua plants.lua add <name> <every-days>     starts watering <name> every <every-days> days; prints "added <name>"
    lua plants.lua water <name> <YYYY-MM-DD>   records a watering on that day; prints "watered <name>"
    lua plants.lua due <YYYY-MM-DD>            prints, one per line and sorted by name, each plant due on or before
                                               that day (never watered counts as due), as "<name> <days overdue>"
    lua plants.lua import <file.csv>           adds every row of a CSV with the header name,every
    lua plants.lua report <file.html>          writes an HTML page listing every plant and its last watering

  Keep the plants in a database, plants.db in the folder the tool runs in. Before writing plants.lua, write its behaviour as Gherkin in
  features/plants.feature and the steps in Lua in features/steps.lua, run with require("test"); the steps may
  call the tool's functions directly or run its commands' logic, as you see fit. You are done when
  `cd /home/plants && lua features/steps.lua` reports every scenario passed. Then answer with one word: DONE.
  """

  test "an agent builds a small tool end to end on its own computer" do
    id = "agent-tool-#{System.unique_integer([:positive])}"
    Moss.Owners.claim(id, "tester")
    Computer.run(id, "mkdir -p /home/plants")

    Moss.AgentLoop.run(
      id,
      @task,
      "Keep going until `lua features/steps.lua` passes, then answer DONE."
    )

    # its own tests, green
    own = Computer.run(id, "cd /home/plants && lua features/steps.lua")
    IO.puts(own.out)
    assert own.code == 0 or own.out =~ ~r/(\d+) of \1 scenarios passed/

    # and the tool does what was asked, driven from here
    sh = fn line -> Computer.run(id, "cd /home/plants && " <> line) end
    assert %{code: 0} = sh.("rm plants.db")

    Computer.exec(id, %{
      "cwd" => "/home/plants",
      "cmd" => "true",
      "files" => %{"check.csv" => "name,every\nmoss,7\n\"basil, sweet\",2\n"}
    })

    assert %{code: 0, out: "added fern\n"} = sh.("lua plants.lua add fern 3")
    assert %{code: 0} = sh.("lua plants.lua import check.csv")
    assert %{code: 0, out: "watered fern\n"} = sh.("lua plants.lua water fern 2026-10-01")
    assert %{code: 0} = sh.("lua plants.lua water moss 2026-10-01")
    assert %{code: 0} = sh.("lua plants.lua water 'basil, sweet' 2026-10-01")

    assert %{code: 0, out: ""} = sh.("lua plants.lua due 2026-10-02")
    assert %{code: 0, out: "basil, sweet 0\n"} = sh.("lua plants.lua due 2026-10-03")
    assert %{code: 0, out: "basil, sweet 3\nfern 2\n"} = sh.("lua plants.lua due 2026-10-06")

    assert %{code: 0} = sh.("lua plants.lua report report.html")
    assert %{code: 0, out: page} = sh.("cat report.html")
    assert page =~ "fern" and page =~ "2026-10-01" and page =~ "basil, sweet"
  end
end

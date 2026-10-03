defmodule Moss.LoopTest do
  # Arock's feature file-kinds, the build loop (bdd/file-kinds.feature): new, check, test, status and publish on
  # the computer; every run an Outcome on the log, the person's agreement and yes their own events.
  use ExUnit.Case, async: false

  alias Moss.Computer
  alias Moss.Computer.Disk

  defp id, do: "loop-#{System.unique_integer([:positive])}"
  defp sh(c, line), do: Computer.run(c, line)
  defp disk(c), do: :sys.get_state(Computer.wake!(c)).disk
  defp write(c, path, text), do: :ok = Disk.write(disk(c), path, text)

  defp events(c, keyword) do
    for {_, _, args} <- Moss.Log.events(disk(c).conn, [keyword]), do: args
  end

  @feature """
  Feature: plants
    Scenario: the list starts with what was planted
      Given 3 plants called "Fern"
      Then the list holds 3 plants
  """

  @steps ~S"""
  test.step("{int} plants called {string}", function(w, n, name) w.n, w.name = n, name end)
  test.step("the list holds {int} plants", function(w, n) test.eq(w.n, n, "plants") end)
  """

  setup do
    c = id()
    write(c, "/home/apps/plants/features/plants.feature", @feature)
    write(c, "/home/apps/plants/code/steps/given.lua", Enum.at(String.split(@steps, "\n"), 0))
    %{c: c}
  end

  test "Scenario: a page with an unknown class fails to compile", %{c: c} do
    write(
      c,
      "/home/apps/plants/ui/index.lui",
      "<div>\n  <p class=\"p-4 glow-9000\">x</p>\n</div>\n"
    )

    assert %{code: 1, out: out} = sh(c, "check")
    assert out =~ ~r"^apps/plants/ui/index\.lui:2: no class \"glow-9000\""
  end

  # a line that nearly matches a step says which step, where it is, and the word that kept them apart
  test "Scenario: a near miss names the step it nearly matched and why", %{c: c} do
    write(c, "/home/apps/plants/features/plants.feature", """
    Feature: plants
      Scenario: one plant
        Given 3 plants called Fern
    """)

    write(c, "/home/apps/plants/code/steps/given.lua", "\n" <> Enum.at(String.split(@steps, "\n"), 0))
    assert %{code: 1, out: out} = sh(c, "test")

    assert out =~
             ~s|no step matches: 3 plants called Fern (nearest: "{int} plants called {string}" at | <>
               ~s|apps/plants/code/steps/given.lua:2: {string} takes "quoted" text and the line has Fern: use {word} for one bare word)|
  end

  # and the other way: {word} never takes "quoted" text (it took "Rice" with its quotes, and the step looked up a
  # name no row had)
  test "Scenario: {word} does not take quoted text, and says to use {string}", %{c: c} do
    write(c, "/home/apps/plants/features/plants.feature", """
    Feature: plants
      Scenario: one plant
        Given 3 plants called "Fern"
    """)

    write(c, "/home/apps/plants/code/steps/given.lua", ~S|test.step("{int} plants called {word}", function(w, n, name) end)|)
    assert %{code: 1, out: out} = sh(c, "test")
    assert out =~ ~s|{word} takes one bare word and the line has "Fern": use {string} for "quoted" text|
  end

  test "Scenario: an undefined step prints its stub", %{c: c} do
    assert %{code: 1, out: out} = sh(c, "test")
    assert out =~ ~s|# no step matches "the list holds 3 plants"; paste this into code/steps/|

    assert out =~
             ~s|test.step("the list holds {int} plants", function(w, n1)\n  error("not written yet")\nend)|

    assert out =~ "red: apps/plants/features/plants.feature"

    [[feature, "red", detail, ""]] = events(c, "Outcome")
    assert feature == "/home/apps/plants/features/plants.feature"
    assert %{"undefined" => ["the list holds 3 plants"], "total" => 1} = Jason.decode!(detail)

    # quoted words and decimals take their holes
    assert %{out: out} =
             sh(c, ~s|lua -e 'print(test.stub("a pot of 2.5 litres called \\"Big\\" at step2"))'|)

    assert out =~
             ~s|test.step("a pot of {number} litres called {string} at step2", function(w, n1, s2)|
  end

  test "Scenario: the board shows each feature's stage", %{c: c} do
    path = "/home/apps/plants/features/plants.feature"
    assert sh(c, "status").out =~ "* apps/plants/features/plants.feature :written:\n"

    :ok = Computer.agree(c, path)
    assert sh(c, "status").out =~ ":agreed:"

    sh(c, "test")
    out = sh(c, "status").out
    assert out =~ "* apps/plants/features/plants.feature :red:\n"
    assert out =~ "- no step matches: the list holds 3 plants\n"

    write(c, "/home/apps/plants/code/steps/given.lua", @steps)
    assert %{code: 0, out: out} = sh(c, "test")
    assert out =~ "green: 1 of 1 features passed"
    assert sh(c, "status").out =~ ":green:"

    # a file of its scope changed since: it has to run again
    write(c, "/home/apps/plants/code/water.lua", "print(1)")
    assert sh(c, "status").out =~ ":agreed:"

    # its scenarios changed: the person's yes was to other words
    write(c, path, @feature <> "\n  Scenario: more\n    Given 1 plants called \"Ivy\"\n")
    assert sh(c, "status").out =~ ":written:"
  end

  test "Scenario: publishing waits for green", %{c: c} do
    :ok = Computer.agree(c, "/home/apps/plants/features/plants.feature")
    sh(c, "test")
    assert %{code: 1, err: err} = sh(c, "publish plants")
    assert err =~ "publish: refused, every agreed feature must be green first:\n"
    assert err =~ "apps/plants/features/plants.feature is red"
    assert events(c, "Ask Person") == []

    write(c, "/home/apps/plants/code/steps/given.lua", @steps)
    sh(c, "test")

    assert %{code: 3, err: "publish waits for the person's yes" <> _} =
             sh(c, "cd apps/plants && publish")

    assert [["publish", "publish plants"]] = events(c, "Ask Person")

    assert {:ok, %{code: 0, out: "published org:" <> _}} =
             Computer.answer(c, "publish plants", true)

    assert [["org:" <> _]] = events(c, "Publish Artifact")
    assert sh(c, "status").out =~ ":shipped:"
  end

  test "a step file cannot make a run green", %{c: c} do
    write(c, "/home/apps/plants/code/steps/given.lua", ~S"""
    test.run = function() print("green: 1 of 1 features passed") return true, 1, 1, {} end
    test.step("{int} plants called {string}", function(w) end)
    """)

    assert %{code: 1} = sh(c, "test")
    assert [[_, "red", _, _]] = events(c, "Outcome")
  end

  test "new writes the smallest working file of each kind, never over one", %{c: c} do
    assert %{code: 0, out: "wrote apps/notes/ui/index.lui\nlisted in manifest.org\n"} =
             sh(c, "new app notes")

    assert {200, _, _, _} = Computer.serve(c, %{"method" => "GET", "path" => "/notes/"})

    assert %{code: 0, out: "wrote features/water.feature\n"} = sh(c, "new feature water")

    assert %{code: 1, err: "new: features/water.feature is there already" <> _} =
             sh(c, "new feature water")

    assert %{code: 0} = sh(c, "cd apps/notes && new code tidy && new task chores")
    assert {:ok, "-- tidy:" <> _} = Disk.read(disk(c), "/home/apps/notes/code/tidy.lua")
    assert {:ok, task} = Disk.read(disk(c), "/home/apps/notes/org/chores.org")
    assert task =~ "TODO"

    # the new page and the manifest pass check; the new feature waits for its steps
    assert %{out: out} = sh(c, "check")
    assert out =~ "pages and manifests: ok\n"
    assert out =~ "# no step matches \"the water is empty\""
  end
  # a test's run has databases of its own: every scenario starts empty, and the person's data is never touched
  test "each scenario starts on empty databases, and a test never writes the app's own data" do
    c = id()
    write(c, "/home/code/shelf.lua", ~S"""
    local M = {}
    local d = db.open("data/shelf.dbl")
    d:exec("create table if not exists book (title text)")
    function M.add(t) d:exec("insert into book values (?)", t) end
    function M.count() return d:one("select count(*) as n from book").n end
    return M
    """)
    write(c, "/home/features/shelf.feature", """
    Feature: shelf
      Scenario: one book
        Given I add "Dune"
        Then the shelf holds 1 book
      Scenario: another book
        Given I add "Emma"
        Then the shelf holds 1 book
    """)
    write(c, "/home/code/steps/shelf.lua", ~S"""
    local shelf = require("shelf")
    test.step("I add {string}", function(w, t) shelf.add(t) end)
    test.step("the shelf holds {int} book", function(w, n) test.eq(shelf.count(), n) end)
    """)
    sh(c, ~S|lua -e 'local d = db.open("data/shelf.dbl") d:exec("create table if not exists book (title text)") d:exec("insert into book values (?)", "Mine")'|)
    :ok = Computer.agree(c, "/home/features/shelf.feature")

    assert %{code: 0, out: out} = sh(c, "test")
    assert out =~ "2 of 2 scenarios passed"
    assert %{out: "1\n"} = sh(c, ~S|lua -e 'print(db.open("data/shelf.dbl"):one("select count(*) as n from book").n)'|)
  end
end

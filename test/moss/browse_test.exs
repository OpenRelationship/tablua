defmodule Moss.BrowseTest do
  # The page's own steps (sdk/browse.lua): a feature that opens the page, types, presses and reads what it shows
  # tests the page itself, its requests the app's own, the page opened afresh after every press.
  use ExUnit.Case, async: false

  alias Moss.Computer
  alias Moss.Computer.Disk

  defp id, do: "browse-#{System.unique_integer([:positive])}"
  defp disk(c), do: :sys.get_state(Computer.wake!(c)).disk
  defp write(c, path, text), do: :ok = Disk.write(disk(c), path, text)

  @page """
  <lua>
    local d = db.open("data/plants.dbl")
    d:exec("create table if not exists plant (name text, watered int default 0)")
    page.title = "Plants"
    function post.add(req) d:exec("insert into plant (name) values (?)", req.form.name) end
    function post.water(req) d:exec("update plant set watered = 1 where name = ?", req.form.name) end
  </lua>
  <card title="Plants">
    <form post="add"><label for="n">Plant name</label><input id="n" name="name"/><button type="submit">Add</button></form>
    {% for _, p in ipairs(d:query("select * from plant order by name")) do %}
      <p>{{ p.name }} {{ p.watered == 1 and "watered" or "dry" }} <button post="water" vals={{ {name = p.name} }}>Water</button></p>
    {% end %}
  </card>
  """

  @feature """
  Feature: plants
    Scenario: a plant added and watered stays on the page
      When I open the page
      And I type "Fern" into "Plant name"
      And I press "Add"
      And I type "Aloe" into "plant name"
      And I press "Add"
      Then I see "Fern dry"
      And I see "Aloe" before "Fern"
      When I press "Water" for "Fern"
      And I open the page again
      Then I see "Fern watered"
      And I see "Aloe dry"
      And I do not see "Ivy"
  """

  setup do
    c = id()
    write(c, "/home/apps/plants/features/plants.feature", @feature)
    %{c: c}
  end

  test "Scenario: a page that keeps what was added passes by its own steps", %{c: c} do
    write(c, "/home/apps/plants/ui/index.lui", @page)
    assert %{code: 0, out: out} = Computer.run(c, "test")
    assert out =~ "green: 1 of 1"
  end

  test "Scenario: a page that keeps it only in memory fails, as it would for its person", %{c: c} do
    memory =
      @page
      |> String.replace(~s|local d = db.open("data/plants.dbl")|, "plants = plants or {}")
      |> String.replace(~s|d:exec("create table if not exists plant (name text, watered int default 0)")|, "")
      |> String.replace(~s|d:exec("insert into plant (name) values (?)", req.form.name)|,
        "plants[#plants + 1] = {name = req.form.name, watered = 0}")
      |> String.replace(~s|d:exec("update plant set watered = 1 where name = ?", req.form.name)|, "")
      |> String.replace(~s|d:query("select * from plant order by name")|, "plants")

    write(c, "/home/apps/plants/ui/index.lui", memory)
    assert %{code: 1, out: out} = Computer.run(c, "test")
    assert out =~ ~s|the page does not show "Fern dry"|
  end

  test "Scenario: a row shows what was done to it, and no other row does", %{c: c} do
    write(c, "/home/apps/plants/ui/index.lui", @page)

    write(c, "/home/apps/plants/features/plants.feature", """
    Feature: plants
      Scenario: watered
        When I type "Fern" into "Plant name"
        And I press "Add"
        And I type "Aloe" into "Plant name"
        And I press "Add"
        And I press "Water" for "Fern"
        Then I see "watered" for "Fern"
        And I see "watered" for "Aloe"
    """)

    assert %{code: 1, out: out} = Computer.run(c, "test")
    assert out =~ ~s|I see "watered" for "Fern"    PASS|
    assert out =~ ~s|the row of "Aloe" does not show "watered"; it shows: Aloe dry Water|
  end

  test "Scenario: a step file that defines the page's own step is named", %{c: c} do
    write(c, "/home/apps/plants/ui/index.lui", @page)
    write(c, "/home/apps/plants/code/steps/page.lua", ~s|\ntest.step("I see {string}", function(w, s) end)\n|)
    assert %{code: 1, out: out} = Computer.run(c, "test")

    assert out =~
             ~s|apps/plants/code/steps/page.lua:2: "I see {string}" is the computer's own step (the page's, sdk/browse.lua)|
  end

  test "Scenario: a field with no label is found by its placeholder", %{c: c} do
    write(c, "/home/apps/plants/ui/index.lui", String.replace(@page, ~s|<label for="n">Plant name</label><input id="n" name="name"/>|, ~s|<input name="name" placeholder="Plant name"/>|))
    assert %{code: 0} = Computer.run(c, "test")
  end

  test "Scenario: a step file that calls browse is told its steps", %{c: c} do
    write(c, "/home/apps/plants/ui/index.lui", @page)
    write(c, "/home/apps/plants/code/steps/page.lua", ~s|local browse = require("browse")\ntest.step("I go home", function(w) browse.navigate("/") end)\n|)

    write(c, "/home/apps/plants/features/plants.feature", """
    Feature: plants
      Scenario: home
        When I go home
    """)

    assert %{code: 1, out: out} = Computer.run(c, "test")
    assert out =~ ~s|browse has no navigate: the page is used through the computer's own steps|
  end

  test "Scenario: a check answered by a step of the app's own is named in the run", %{c: c} do
    write(c, "/home/apps/plants/ui/index.lui", @page)
    write(c, "/home/apps/plants/code/steps/own.lua", ~s|test.step("the list has {string}", function(w, s) end)\n|)

    write(c, "/home/apps/plants/features/plants.feature", """
    Feature: plants
      Scenario: added
        When I type "Fern" into "Plant name"
        And I press "Add"
        Then I see "Fern" in the list
        And the list has "Fern"
    """)

    assert %{code: 0} = Computer.run(c, "test")
    [{_, _, [_, "green", detail | _]} | _] = Moss.Log.events(disk(c).conn, ["Outcome"])
    assert Jason.decode!(detail)["checked"] == [~s|the list has "Fern"|]
  end

  test "Scenario: a button the page lacks names the buttons it has", %{c: c} do
    write(c, "/home/apps/plants/ui/index.lui", @page)

    write(c, "/home/apps/plants/features/plants.feature", """
    Feature: plants
      Scenario: no such button
        When I open the page
        And I press "Plant"
    """)

    assert %{code: 1, out: out} = Computer.run(c, "test")
    assert out =~ ~s|no button "Plant" on the page; its buttons: "Add"|
  end

  test "Scenario: a row's button whose vals carry only an id is found by its row", %{c: c} do
    by_id =
      @page
      |> String.replace(~s|set watered = 1 where name = ?", req.form.name|, ~s|set watered = 1 where rowid = ?", req.form.id|)
      |> String.replace(~s|select * from plant order by name|, ~s|select rowid as id, * from plant order by name|)
      |> String.replace(~s|vals={{ {name = p.name} }}|, ~s|vals={{ {id = p.id} }}|)

    write(c, "/home/apps/plants/ui/index.lui", by_id)
    assert %{code: 0, out: out} = Computer.run(c, "test")
    assert out =~ "green: 1 of 1"
  end

  test "Scenario: a row the scenario never made is named, each scenario starting empty", %{c: c} do
    write(c, "/home/apps/plants/ui/index.lui", @page)

    write(c, "/home/apps/plants/features/plants.feature", """
    Feature: plants
      Scenario: water a plant never added
        When I open the page
        And I press "Water" for "Fern"
    """)

    assert %{code: 1, out: out} = Computer.run(c, "test")
    assert out =~ ~s|nothing on the page shows "Fern", so it has no "Water" for it: each scenario starts from an empty app|
  end

  test "Scenario: a check on what only an earlier scenario typed says each scenario starts empty", %{c: c} do
    write(c, "/home/apps/plants/ui/index.lui", @page)

    write(c, "/home/apps/plants/features/plants.feature", """
    Feature: plants
      Scenario: one plant
        When I type "Fern" into "Plant name"
        And I press "Add"
        Then I see "Fern"
      Scenario: in order
        When I type "Aloe" into "Plant name"
        And I press "Add"
        Then I see "Aloe" before "Fern"
    """)

    assert %{code: 1, out: out} = Computer.run(c, "test")
    assert out =~ ~s|I see "Fern"    PASS|
    assert out =~ ~s|"Fern" was typed only in an earlier scenario, and each scenario starts from an empty app|
  end

  # the same page written in org and Lua (arock issue #2; owner, 2026-10-04): its Code runs on every request, its
  # Page returns nodes built with ui, and an element names an action by its bare name
  @org_page """
  * Code
  #+begin_src lua
  local d = db.open("data/plants.dbl")
  d:exec("create table if not exists plant (name text, watered int default 0)")
  page.title = "Plants"
  function post.add(req) d:exec("insert into plant (name) values (?)", req.form.name) end
  function post.water(req) d:exec("update plant set watered = 1 where name = ?", req.form.name) end
  #+end_src
  * Page
  #+begin_src lua
  local rows = {}
  for _, p in ipairs(d:query("select * from plant order by name")) do
    rows[#rows + 1] = ui.p{ p.name .. " " .. (p.watered == 1 and "watered" or "dry") .. " ",
      ui.button{ "Water", post = "water", vals = { name = p.name } } }
  end
  return ui.card{ title = "Plants",
    ui.form{ post = "add", ui.label{ ["for"] = "n", "Plant name" }, ui.input{ id = "n", name = "name" },
      ui.button{ type = "submit", "Add" } },
    rows }
  #+end_src
  """

  test "Scenario: a page in org and Lua passes the same steps, and is served before a .lui of its name", %{c: c} do
    write(c, "/home/apps/plants/ui/index.org", @org_page)
    write(c, "/home/apps/plants/ui/index.lui", "<p>the old page</p>")
    assert %{code: 0, out: out} = Computer.run(c, "test")
    assert out =~ "green: 1 of 1"
  end

  test "Scenario: an org page's errors name the file's own line, and an unknown action is refused", %{c: c} do
    broken = String.replace(@org_page, ~s|page.title = "Plants"|, ~s|page.title = nothing.here|)
    write(c, "/home/ui/index.org", broken)
    assert {500, _, body, _} = Computer.serve(c, %{"method" => "GET", "path" => "/"})
    assert body =~ "ui/index.org:5:"
    write(c, "/home/ui/index.org", String.replace(@org_page, ~s|ui.form{ post = "add"|, ~s|ui.form{ post = "plant"|))
    assert {500, _, body, _} = Computer.serve(c, %{"method" => "GET", "path" => "/"})
    assert body =~ ~s|post = "plant" names no action|
  end

  test "new orgpage writes a page in org and Lua that serves, and an org-pages run's help names no .lui", %{c: c} do
    assert %{code: 0, out: "wrote ui/index.org\n"} = Computer.run(c, "new orgpage index")
    assert {200, _, body, _} = Computer.serve(c, %{"method" => "GET", "path" => "/"})
    assert IO.iodata_to_binary(body) =~ "Nothing yet"
    assert Computer.run(c, "check").out =~ "pages and manifests: ok"

    help =
      Enum.map_join(["help org-pages" | Enum.map(Moss.Computer.Help.topics(), &"help org-pages #{&1}")], "\n",
        &Computer.run(c, &1).out)

    assert help =~ "ui/*.org"
    assert help =~ "new orgpage"
    refute help =~ ".lui"
    refute Computer.run(c, "help code").out =~ "orgpage"
  end
end

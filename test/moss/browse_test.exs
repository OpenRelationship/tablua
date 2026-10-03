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
end

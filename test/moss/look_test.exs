defmodule Moss.LookTest do
  # The agent opens its app as the person's browser lays it out (Arock feature look): moss-browser's look, Blitz in
  # WebAssembly in a node of its own, given the page with the utilities' CSS Shroomi wrote, and Basecoat's
  # stylesheet. Needs priv/look.wasm (mix moss.look).
  use ExUnit.Case, async: false

  alias Moss.Computer
  alias Moss.Computer.Disk

  @moduletag :look

  defp cid, do: "look-#{System.unique_integer([:positive])}"

  defp put_page(c, text),
    do: :ok = Disk.write(:sys.get_state(Computer.wake!(c)).disk, "/home/ui/index.lui", text)

  test "what the stylesheet hides is not read, and its controls are not listed" do
    c = cid()

    put_page(c, ~S"""
    <h1>Plants</h1>
    <div class="hidden"><p>the gardener's notes</p><button>Delete all</button></div>
    <button>Water</button>
    """)

    assert %{code: 0, out: out} = Computer.run(c, "open app")
    assert out =~ "(laid out at 1280 px)"
    refute out =~ "the gardener's notes"
    assert %{out: ui} = Computer.run(c, "ui")
    assert ui =~ ~s(button "Water")
    refute ui =~ "Delete all"
  end

  @menu ~S"""
  <nav class="hidden md:flex"><a href="about">About</a></nav>
  <button class="md:hidden">Menu</button>
  """

  test "the agent sees the phone's page, and the desktop's" do
    c = cid()
    put_page(c, @menu)

    assert %{code: 0, out: out} = Computer.run(c, "open app --width 390")
    assert out =~ "(laid out at 390 px)"
    assert %{out: ui} = Computer.run(c, "ui")
    assert ui =~ ~s(button "Menu")
    refute ui =~ ~s(link "About")

    assert %{code: 0} = Computer.run(c, "open app --width 1280")
    assert %{out: ui} = Computer.run(c, "ui")
    assert ui =~ ~s(link "About")
    refute ui =~ ~s(button "Menu")
  end

  test "the width and theme are kept while the computer sleeps, and a woken tab is laid out at them" do
    c = cid()
    put_page(c, @menu)

    assert %{out: out} = Computer.run(c, "open app --width 390 --dark")
    assert out =~ "(laid out at 390 px, dark)"
    :ok = Computer.sleep(c)
    assert %{out: page} = Computer.run(c, "page")
    assert page =~ "Menu"
    assert %{out: ui} = Computer.run(c, "ui")
    refute ui =~ ~s(link "About")
  end

  test "a closed dialog is not on the page; an open one is" do
    c = cid()

    put_page(c, ~S"""
    <lua>local open = req.query.d == "1"</lua>
    <a href="?d=1">New plant</a>
    <dialog open={{ open }}><input name="kind" label="Kind"/></dialog>
    """)

    assert %{code: 0} = Computer.run(c, "open app")
    refute Computer.run(c, "ui").out =~ ~s(field "Kind")
    assert %{code: 0} = Computer.run(c, ~s(click "New plant"))
    assert Computer.run(c, "ui").out =~ ~s(field "Kind")
  end

  test "Shroomi's stylesheet is laid out with the app's page" do
    c = cid()

    # Basecoat hides a dropdown's indicator (.dropdown-menu [data-indicator] { visibility: hidden }); the page does not
    put_page(c, ~S"""
    <div class="dropdown-menu"><p>Sort by name <span data-indicator>chosen</span></p></div>
    """)

    assert %{code: 0, out: out} = Computer.run(c, "open app")
    assert out =~ "Sort by name"
    refute out =~ "chosen"
  end
  test "layout faults are named, each with its element and its line in the page's source" do
    c = cid()

    put_page(c, ~S"""
    <h1>Plants</h1>
    <button class="w-0 h-0 p-0 border-0 overflow-hidden">Save</button>
    <input name="email" class="block w-48"/>
    <div class="absolute top-0 left-0 w-80 h-40 bg-background">Banner</div>
    <table class="w-[900px]"><tbody><tr><td>wide</td></tr></tbody></table>
    """)

    assert %{code: 1, out: out} = Computer.run(c, "look --width 390")
    assert out =~ "ui/index.lui at 390 px: 3 faults"
    assert out =~ ~s(ui/index.lui:2  button "Save" cannot be seen: it is 0 by 0 px)
    assert out =~ ~s[ui/index.lui:3  field "email" cannot be clicked: <div> "Banner" (line 4) is over it]
    assert out =~ ~s(ui/index.lui:5  <table> "wide" runs off the screen: 900 px wide)
  end

  test "text too faint to read in the dark theme is named, with its colours" do
    c = cid()
    put_page(c, ~S"""
    <p class="text-muted">sown in spring</p>
    """)

    assert %{code: 1, out: out} = Computer.run(c, "look --dark")
    # Basecoat's dark background, put on by the theme the look sets in place of Shroomi's script
    assert out =~ ", dark: "
    assert [_, ratio] = Regex.run(~r/<p> "sown in spring" is too faint: #[0-9a-f]{6} on #0a0a0a, ([\d.]+) to 1/, out)
    assert String.to_float(ratio) < 4.5
  end

  test "a page a person can use has no faults" do
    c = cid()
    put_page(c, ~S"""
    <h1>Plants</h1>
    <button>Water</button>
    """)

    assert %{code: 0, out: out} = Computer.run(c, "look")
    assert out =~ "nothing a person could not use"
  end
end

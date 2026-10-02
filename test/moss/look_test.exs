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
end

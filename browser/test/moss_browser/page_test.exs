defmodule MossBrowser.PageTest do
  # A page read as an accessibility tree (Arock feature browser): roles, states, names as a screen reader gives
  # them, what is hidden, and a table cell with its header.
  use ExUnit.Case, async: true

  alias MossBrowser.Page

  describe "the accessibility tree" do
    defp ui(html), do: Page.outline(Page.new("https://example.com/", html))

    test "role makes the control, and states are shown" do
      out =
        ui("""
        <div role="button">Save</div><span role="checkbox" aria-checked="true">Agree</span>
        <button aria-expanded="false" aria-haspopup="menu">Menu</button>
        <input name="c" aria-label="City" required disabled>
        """)

      assert out =~ ~s(button "Save")
      assert out =~ ~S[checkbox "Agree" (checked)]
      assert out =~ ~S[button "Menu" (collapsed)]
      assert out =~ ~S[field "City" (required, disabled)]
    end

    test "hidden things are not read" do
      page =
        Page.new("https://example.com/", """
        <p>shown</p><div aria-hidden="true">ghost one <a href="/a">A</a></div>
        <div hidden>ghost two <button>B</button></div><p style="color:red; display: none">ghost three</p>
        <span style="visibility:hidden">ghost four</span>
        """)

      refute Page.text(page) =~ "ghost"
      assert Page.text(page) =~ "shown"
      assert Enum.reject(page.controls, &(&1.role == "hidden")) == []
    end

    test "a page that hides nearly all its words until its scripts run is read anyway, and says so" do
      posts = Enum.map_join(1..40, &"<p>Post #{&1} about the launch window</p>")
      page = Page.new("https://example.com/", "<p>Log in</p><div hidden>#{posts}</div>")
      assert Page.text(page) =~ "Post 40 about the launch"
      assert Enum.any?(page.notes, &(&1 =~ "hides most of its words"))

      menu = Enum.map_join(1..40, &"<a href='/#{&1}'>Menu item #{&1}</a>")
      body = Enum.map_join(1..20, &"<p>Visible paragraph #{&1} with several words in it</p>")
      page = Page.new("https://example.com/", "<div hidden>#{menu}</div>#{body}")
      refute Page.text(page) =~ "Menu item"
      assert page.notes == []
    end

    test "a control is named as a screen reader names it" do
      out =
        ui("""
        <span id="l1">Your city</span><input aria-labelledby="l1" name="x" placeholder="e.g. Oslo">
        <button title="Close"></button><input name="q" placeholder="Search">
        <input name="d" aria-describedby="h"><span id="h">As on your passport</span>
        """)

      assert out =~ ~s(field "Your city")
      assert out =~ ~s(button "Close")
      assert out =~ ~s(field "Search")
      assert out =~ "As on your passport"
    end

    test "a table cell is read with its header" do
      page =
        Page.new("https://example.com/", """
        <table><tr><th>Plan</th><th>Price</th></tr><tr><td>Pro</td><td>$12</td></tr></table>
        """)

      assert Page.text(page) =~ "Plan: Pro · Price: $12"
    end
  end
end

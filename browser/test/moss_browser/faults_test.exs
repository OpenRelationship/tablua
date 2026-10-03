defmodule Moonflower.FaultsTest do
  # Layout faults (Arock feature look): what a look shows that a person could not use. Needs priv/look.wasm, v0.2.0
  # or later (it says how each box is placed and painted).
  use ExUnit.Case, async: false

  alias Moonflower.Look
  alias Moonflower.Look.Faults

  @moduletag :look
  @wasm Path.expand("../../priv/look.wasm", __DIR__)

  setup_all do
    sha = :crypto.hash(:sha384, File.read!(@wasm)) |> Base.encode16(case: :lower)
    {:ok, node} = Look.Node.start_link(path: @wasm, sha384: sha, name: nil)
    %{node: node}
  end

  defp faults(node, html, opts \\ []) do
    {:ok, look} = Look.look(node, html, [base: "https://example.com/"] ++ opts)
    Faults.faults(look)
  end

  defp kinds(faults), do: for(f <- faults, do: {f.kind, words(f.element)})
  defp words({_, _, kids}), do: Moonflower.Page.Attrs.words(kids) |> String.trim()

  test "a page a person can use has no faults", %{node: node} do
    html = ~s(<h1>Plants</h1><p>A list.</p><button>Add</button><a href="/about">About</a>)
    assert faults(node, html, width: 390) == []
  end

  test "a button of no size cannot be seen", %{node: node} do
    html = ~s(<button style="width:0;height:0;padding:0;border:0;overflow:hidden">Save</button>)
    assert [{:unseen, "Save"}] = kinds(faults(node, html))
  end

  test "a field under a positioned element cannot be clicked", %{node: node} do
    html = """
    <input name="email" style="display:block;width:200px;height:30px">
    <div style="position:absolute;top:0;left:0;width:300px;height:100px;background:#fff">Banner</div>
    """

    assert [%{kind: :covered, element: {"input", _, _}, by: {"div", _, _}}] = faults(node, html)
  end

  test "a control above a positioned element, or inside it, is not covered", %{node: node} do
    html = """
    <div style="position:fixed;top:0;left:0;width:300px;height:100px;background:#fff">
      <button>Close</button>
    </div>
    <div style="position:absolute;top:0;left:0;width:300px;height:100px;z-index:-1">behind</div>
    <button style="position:relative;margin-top:150px">Open</button>
    """

    refute Enum.any?(faults(node, html), &(&1.kind == :covered))
  end

  test "a table wider than a phone runs off the screen, unless something scrolls it", %{
    node: node
  } do
    wide = ~s(<table style="width:900px"><tr><td>wide</td></tr></table>)
    assert [{:off_screen, "wide"}] = kinds(faults(node, wide, width: 390))

    scrolled = ~s(<div style="overflow-x:auto">#{wide}</div>)
    assert faults(node, scrolled, width: 390) == []
  end

  test "faint text is named with its colours and ratio", %{node: node} do
    html = """
    <div style="background:#0a0a0a"><p style="color:#444444">muted</p><p style="color:#fafafa">clear</p></div>
    """

    assert [%{kind: :faint, color: "#444444", background: "#0a0a0a", ratio: ratio}] =
             faults(node, html)

    assert ratio < 4.5
  end
end

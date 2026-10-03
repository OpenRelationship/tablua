defmodule MossBrowser.LookTest do
  # The look (Arock feature look): a page laid out by Blitz in WebAssembly, in a node of its own, each look a fresh
  # instance under fuel and memory limits, the module checked by its hash. Needs priv/look.wasm (CI builds it).
  use ExUnit.Case, async: false

  alias MossBrowser.Look

  @moduletag :look
  @wasm Path.expand("../../priv/look.wasm", __DIR__)

  setup_all do
    sha = :crypto.hash(:sha384, File.read!(@wasm)) |> Base.encode16(case: :lower)
    {:ok, node} = Look.Node.start_link(path: @wasm, sha384: sha, name: nil)
    %{node: node, sha: sha}
  end

  @page """
  <html><head><style>
  .secret { display: none }
  .menu { display: none }
  @media (min-width: 768px) { .menu { display: flex } .menu-button { display: none } }
  .ghost { visibility: hidden }
  </style></head><body>
  <nav class="menu"><a href="/a">Plants</a></nav>
  <button class="menu-button">Menu</button>
  <div class="secret"><p>hidden by the stylesheet</p></div>
  <p class="ghost">invisible</p>
  <button style="width:0;height:0;padding:0;border:0">Save</button>
  <table style="width:900px"><tr><td>wide</td></tr></table>
  <dialog><input name="d"></dialog>
  </body></html>
  """

  defp shown(node, width) do
    {:ok, look} = Look.look(node, @page, width: width, base: "https://example.com/")

    for {tag, text} <- [
          {"a", "Plants"},
          {"button", "Menu"},
          {"p", "hidden by the stylesheet"},
          {"p", "invisible"},
          {"input", nil}
        ],
        into: %{},
        do: {text || tag, Look.shown?(look, tag, text)}
  end

  test "what the stylesheet hides is hidden, at the width it is laid out at", %{node: node} do
    assert shown(node, 1280) == %{
             "Plants" => true,
             "Menu" => false,
             "hidden by the stylesheet" => false,
             "invisible" => false,
             "input" => false
           }

    assert %{"Plants" => false, "Menu" => true} = shown(node, 390)
  end

  test "boxes: a button of no size, and a table wider than a phone", %{node: node} do
    {:ok, look} = Look.look(node, @page, width: 390, base: "https://example.com/")
    assert [%{w: 0, h: 0}] = Look.boxes(look, "button", "Save")
    assert [%{w: 900}] = Look.boxes(look, "table", nil)
    assert look.width == 390
  end

  test "a page the module cannot lay out is an error, and the next look starts clean", %{
    node: node
  } do
    # a relative stylesheet with no address to resolve it against panics Blitz
    assert {:error, :failed} =
             Look.look(node, ~s(<link rel="stylesheet" href="x.css"><p>hi</p>), base: nil)

    assert {:ok, look} = Look.look(node, "<p>hi</p>", base: "https://example.com/")
    assert Look.shown?(look, "p", "hi")
  end

  test "a costly page is stopped", %{node: node} do
    assert {:error, :too_costly} =
             Look.look(node, @page, base: "https://example.com/", fuel: 1_000)
  end

  test "a module whose hash differs is refused", %{sha: sha} do
    wrong = String.duplicate("0", byte_size(sha))
    assert {:error, :hash} = Look.Module.load(@wasm, wrong)
  end

  test "the module is given no directory, so it can open no file", %{node: node} do
    # the page asks for nothing it could reach; what the module can reach is checked in Look.Run: no preopen,
    # no environment, no arguments
    assert Look.Run.wasi_options().preopen == []
    assert Look.Run.wasi_options().env == %{}
    assert {:ok, _} = Look.look(node, "<p>x</p>", base: "https://example.com/")
  end

  test "a page read through its look reads only what is shown", %{node: node} do
    {:ok, look} = Look.look(node, @page, width: 390, base: "https://example.com/")
    page = MossBrowser.Page.looked("https://example.com/", look)
    text = MossBrowser.Page.text(page)

    refute text =~ "hidden by the stylesheet"
    refute text =~ "Plants"
    assert text =~ "wide"
    refute MossBrowser.Page.outline(page) =~ ~s(field "d")
    assert MossBrowser.Page.outline(page) =~ ~s(button "Menu")
    assert Enum.any?(page.notes, &(&1 =~ "390"))
  end

  test "what is invisible is not read, but a child that shows itself is", %{node: node} do
    html = """
    <style>.ghost { visibility: hidden } .back { visibility: visible }</style>
    <div class="ghost">unseen <span class="back">seen again</span></div>
    <div style="display: contents"><p>inside contents</p></div>
    """

    {:ok, look} = Look.look(node, html, base: "https://example.com/")
    text = MossBrowser.Page.text(MossBrowser.Page.looked("https://example.com/", look))
    refute text =~ "unseen"
    assert text =~ "seen again"
    assert text =~ "inside contents"
  end

  test "CSS given beside the page is laid out with it, and does not join the page", %{node: node} do
    css = ".secret { display: none }"

    {:ok, look} =
      Look.look(node, ~s(<p class="secret">gone</p><p>kept</p>),
        css: css,
        base: "https://example.com/"
      )

    refute Look.shown?(look, "p", "gone")
    assert Look.shown?(look, "p", "kept")
    refute MossBrowser.HTML.to_html(look.tree) =~ "display: none"
  end

  test "a crash of the look node stops nothing, and the next look starts a new one", %{node: node} do
    Look.Node.kill(node)
    assert {:ok, look} = Look.look(node, "<p>back</p>", base: "https://example.com/")
    assert Look.shown?(look, "p", "back")
  end

  test "a selector list holding :has() still applies (Basecoat's field labels)", %{node: node} do
    html = ~S"""
    <style>.field>label,label:has(>.x){width:fit-content}</style>
    <div class="field"><label>Name</label></div>
    """

    {:ok, look} = Look.look(node, html, width: 390, base: "https://example.com/")
    assert [%{w: w}] = Look.boxes(look, "label")
    assert w < 100
  end

  test "Blitz's own nodes are not elements the page's parser missed", %{node: node} do
    html = ~S"""
    <style>p::before{content:"x"}</style><div>a<p>b</p>c</div><details><summary>s</summary>x</details>
    """

    {:ok, look} = Look.look(node, html, base: "https://example.com/")
    assert look.unmarked == 0

    # nor is CSS given beside a whole page: it goes in the page's head, so the page's own <head> stays its own
    page = "<!doctype html><html><head><title>t</title></head><body>" <> html <> "</body></html>"
    {:ok, look} = Look.look(node, page, base: "https://example.com/", css: "p { color: red }")
    assert look.unmarked == 0
  end
end

defmodule MossBrowser.HostileTest do
  # Pages built to break the look (Arock feature look): each ends as a look, too costly, failed, or the look node
  # down and started again; never a hang, never a fault in the node that asked, and the next look is a clean one.
  # Needs priv/look.wasm.
  use ExUnit.Case, async: false

  alias MossBrowser.Look

  @moduletag :look
  @moduletag timeout: 600_000
  @wasm Path.expand("../../priv/look.wasm", __DIR__)
  @limit 30_000

  setup_all do
    sha = :crypto.hash(:sha384, File.read!(@wasm)) |> Base.encode16(case: :lower)
    {:ok, node} = Look.Node.start_link(path: @wasm, sha384: sha, name: nil)
    %{node: node}
  end

  @pages [
    deep_nesting: String.duplicate("<div>", 200_000) <> "x",
    deep_inline_nesting: String.duplicate("<b><i>", 50_000) <> "x",
    many_elements: String.duplicate("<p>words <span>and more</span></p>", 200_000),
    long_text: "<p>" <> String.duplicate("a", 20_000_000) <> "</p>",
    long_word_narrow: ~s(<div style="width:1px">) <> String.duplicate("w", 2_000_000) <> "</div>",
    huge_stylesheet:
      "<style>" <> Enum.map_join(1..200_000, fn i -> ".c#{i} p > a:hover{color:red;margin:#{i}px}" end) <>
        "</style><p class=c1>x</p>",
    has_on_every_element:
      "<style>*:has(* *:has(* * *)){color:red} :is(*:has(*) *:has(*)) *{color:blue}</style>" <>
        String.duplicate("<div><span><a>x</a></span>", 3_000) <> String.duplicate("</div>", 3_000),
    nth_child_of_storm:
      "<style>li:nth-child(2n+1 of :has(b), :is(li)):nth-last-child(3n of *){color:red}</style><ul>" <>
        String.duplicate("<li><b>x</b></li>", 50_000) <> "</ul>",
    var_chain:
      "<style>:root{" <> Enum.map_join(1..20_000, fn i -> "--v#{i}:calc(var(--v#{i - 1}) + 1px);" end) <>
        "--v0:1px}p{width:var(--v20000)}</style><p>x</p>",
    var_cycle: "<style>:root{--a:var(--b);--b:var(--a)}p{width:var(--a)}</style><p>x</p>",
    var_blowup:
      "<style>:root{--a:xxxxxxxxxx;" <>
        Enum.map_join(?b..?z, fn c -> "--#{<<c>>}:var(--#{<<c - 1>>}) var(--#{<<c - 1>>}) var(--#{<<c - 1>>});" end) <>
        "}p::before{content:var(--z)}</style><p>x</p>",
    nested_calc: "<style>p{width:" <> String.duplicate("calc(1px + ", 20_000) <> "1px" <> String.duplicate(")", 20_000) <> "}</style><p>x</p>",
    giant_sizes:
      ~s(<div style="width:1e9px;height:1e9px;font-size:1e6px;padding:1e9px;border:1e9px solid">) <>
        String.duplicate("big text ", 1000) <> "</div>",
    grid_explosion:
      ~s|<div style="display:grid;grid-template-columns:repeat(10000,1fr);grid-template-rows:repeat(10000,1fr)">| <>
        String.duplicate("<i>x</i>", 20_000) <> "</div>",
    flex_wrap_storm: ~s(<div style="display:flex;flex-wrap:wrap">) <> String.duplicate(~s(<span style="flex:1 1 1px">x</span>), 200_000) <> "</div>",
    table_explosion: "<table>" <> String.duplicate("<tr>" <> String.duplicate("<td>x</td>", 400) <> "</tr>", 500) <> "</table>",
    colspan_rowspan: ~s(<table><tr><td colspan="1000000" rowspan="65534">x</td></tr></table>),
    import_loops: ~s|<style>@import url("a.css");@import url("http://127.0.0.1/");@import "data:text/css,p{color:red}";</style><p>x</p>|,
    parser_confusion:
      ~s|<svg><style><img src=x onerror=alert(1)></style></svg><math><mtext><table><mglyph><style><img src=x></style>| <>
        ~s(<noscript><p title="</noscript><img src=x>"></noscript><template><template><table><form><select><option>) <>
        String.duplicate("<table><caption><table>", 5_000),
    nul_and_controls: "<p>" <> String.duplicate(<<0, 1, 0xFE, 0xFF, 0xC0, 0x80>>, 100_000) <> "</p>",
    counter_storm:
      "<style>li{counter-increment:a 2147483647} li::before{content:counters(a, '.') counters(a, '.')}</style><ol>" <>
        String.duplicate("<li><ol><li>x</li></ol></li>", 20_000) <> "</ol>",
    font_face_flood:
      "<style>" <> Enum.map_join(1..5_000, fn i -> "@font-face{font-family:f#{i};src:url(data:font/ttf;base64,AAAA)}" end) <>
        "p{font-family:" <> Enum.map_join(1..5_000, ",", &"f#{&1}") <> "}</style><p>x</p>"
  ]

  for {name, html} <- @pages do
    @tag hostile: name
    test "#{name} ends as a look, too costly or failed, within the limit, and the next look is clean", %{node: node} do
      html = unquote(Macro.escape(html))
      t0 = System.monotonic_time(:millisecond)
      task = Task.async(fn -> Look.look(node, html, base: "https://example.com/", timeout: 20_000) end)

      result =
        case Task.yield(task, @limit) || Task.shutdown(task, :brutal_kill) do
          {:ok, r} -> r
          nil -> :hung
        end

      said = if match?({:ok, _}, result), do: "laid out", else: inspect(result)
      IO.puts("#{unquote(name)}: #{said}, #{System.monotonic_time(:millisecond) - t0} ms")

      assert match?({:ok, %Look{}}, result) or result in [{:error, :too_costly}, {:error, :failed}, {:error, :down}],
             "#{unquote(name)}: #{inspect(result, limit: 3)}"

      assert {:ok, look} = Look.look(node, "<p>after</p>", base: "https://example.com/")
      assert Look.shown?(look, "p", "after")
    end
  end
end

# What the computer's browser costs and reads on the web (Arock feature browser):
#
#   mix run --no-start bench/web.exs [sites_file] [out.jsonl]
#
# Each address in `sites_file` (bench/web_sites.txt, 55 sites an agent is likely to need, grouped by kind) is
# opened in the computer's browser (`Computer.Browser`, a computer's state without its disk), and measured:
#
#   heap    the tab on the computer's heap (its parse tree, before the browser feature)
#   total   the tab with its binaries (term_to_binary): what it holds in memory, off the heap included
#   file    what the computer's file keeps for the browser after the command (the session, written each command)
#   open    the tokens `open` costs (its output, 4 bytes a token)
#   words, controls   what the page read as
#
# It calls only `Browser.run/4`, so it runs on a Moss from before the feature too: check out an older commit and
# run it there to compare (the numbers in feature.md's table came that way). Nothing here runs a page's script.
alias Moonflower.Page
alias Moss.Computer.Browser

{:ok, _} = Application.ensure_all_started(:req)

[file, out] =
  case System.argv() do
    [] -> ["bench/web_sites.txt", "tmp/web.jsonl"]
    [f] -> [f, "tmp/web.jsonl"]
    [f, o | _] -> [f, o]
  end

sites =
  file
  |> File.read!()
  |> String.split("\n")
  |> Enum.reduce({"", []}, fn line, {kind, acc} ->
    case String.trim(line) do
      "# kind: " <> k -> {k, acc}
      "#" <> _ -> {kind, acc}
      "" -> {kind, acc}
      url -> {kind, [{kind, url} | acc]}
    end
  end)
  |> elem(1)
  |> Enum.reverse()

word = :erlang.system_info(:wordsize)

# the session as the computer keeps it: Browser.kept/1 since the feature, the whole browser before it
kept = fn b -> if function_exported?(Browser, :kept, 1), do: Browser.kept(b), else: b end
text = fn page -> if function_exported?(Page, :text, 1), do: Page.text(page), else: page.text end

measure = fn kind, url ->
  t = System.monotonic_time(:millisecond)

  {code, said, err, state} =
    try do
      Browser.run("open", [url], "", %{browser: Browser.new()})
    rescue
      e -> {99, "", Exception.message(e), nil}
    end

  ms = System.monotonic_time(:millisecond) - t
  tab = state && Browser.front(state)

  if tab && tab.page do
    shown = Enum.reject(tab.page.controls, &(&1.role == "hidden"))

    %{
      kind: kind,
      url: url,
      ok: true,
      code: code,
      ms: ms,
      heap: :erts_debug.flat_size(tab) * word,
      total: byte_size(:erlang.term_to_binary(tab)),
      file: byte_size(:erlang.term_to_binary(kept.(state.browser))),
      open: div(byte_size(said), 4),
      words: length(String.split(text.(tab.page))),
      controls: length(shown)
    }
  else
    %{kind: kind, url: url, ok: false, ms: ms, why: String.trim(err)}
  end
end

results =
  sites
  |> Task.async_stream(fn {k, u} -> measure.(k, u) end,
    max_concurrency: 4,
    timeout: 120_000,
    ordered: true
  )
  |> Enum.map(fn {:ok, r} -> r end)

File.mkdir_p!(Path.dirname(out))
File.write!(out, Enum.map_join(results, "\n", &JSON.encode!/1) <> "\n")

kb = fn n -> "#{Float.round(n / 1024, 1)}K" end
pad = &String.pad_trailing/2
lead = &String.pad_leading/2

IO.puts(
  pad.("site", 40) <>
    lead.("heap", 9) <>
    lead.("total", 9) <>
    lead.("file", 9) <>
    lead.("open", 8) <>
    lead.("words", 8) <> lead.("ctrls", 7) <> lead.("ms", 7)
)

for r <- results do
  host = r.url |> URI.parse() |> then(&(&1.host <> (&1.path || ""))) |> String.slice(0, 38)

  if r.ok do
    IO.puts(
      pad.(host, 40) <>
        lead.(kb.(r.heap), 9) <>
        lead.(kb.(r.total), 9) <>
        lead.(kb.(r.file), 9) <>
        lead.("#{r.open}t", 8) <>
        lead.("#{r.words}", 8) <> lead.("#{r.controls}", 7) <> lead.("#{r.ms}", 7)
    )
  else
    IO.puts(pad.(host, 40) <> "  failed: " <> String.slice(r.why, 0, 60))
  end
end

ok = Enum.filter(results, & &1.ok)
median = fn xs -> xs |> Enum.sort() |> Enum.at(div(length(xs), 2)) end
top = fn xs -> Enum.max(xs, fn -> 0 end) end

IO.puts("\n#{length(ok)} of #{length(results)} opened")

for {name, key, f} <- [
      {"heap", :heap, kb},
      {"total", :total, kb},
      {"file", :file, kb},
      {"open", :open, &"#{&1}t"}
    ],
    ok != [] do
  xs = Enum.map(ok, &Map.fetch!(&1, key))

  IO.puts(
    "#{pad.(name, 6)} median #{f.(median.(xs))}, largest #{f.(top.(xs))}, all #{f.(Enum.sum(xs))}"
  )
end

IO.puts("rows: #{out}")

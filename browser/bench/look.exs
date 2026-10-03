# The look under load (Arock feature look): looks run 1, 8, 32 and 64 at a time through one look node, then two,
# over a folder of pages (each a JSON file of html, css and base, as an agreement corpus is built). Prints time per
# look (p50, p99), looks a second, looks a second per scheduler, and the look nodes' memory (resident, peak).
#
#   ERL_FLAGS="+S 8" mix run bench/look.exs <pages dir> [looks per round]
#
# +S 8 gives the node and its look nodes 8 schedulers, as on an 8 vCPU server. Needs priv/look.wasm.
alias MossBrowser.Look

[dir | rest] = System.argv()
per_round = String.to_integer(List.first(rest) || "128")
wasm = Path.expand("priv/look.wasm")
sha = :crypto.hash(:sha384, File.read!(wasm)) |> Base.encode16(case: :lower)

pages =
  for f <- Path.wildcard(Path.join(dir, "*.json")) |> Enum.sort(),
      p = JSON.decode!(File.read!(f)),
      do: {p["kind"], p["html"], p["css"], p["base"]}

IO.puts("#{length(pages)} pages, #{per_round} looks a round, #{System.schedulers_online()} schedulers here")

nodes = fn n ->
  for _ <- 1..n do
    {:ok, node} = Look.Node.start_link(path: wasm, sha384: sha, name: nil)
    {:ok, peer} = Look.Node.peer(node)
    {node, :peer.call(peer, :os, :getpid, [])}
  end
end

rss = fn pids ->
  {out, 0} = System.cmd("ps", ["-o", "rss=", "-p", Enum.join(pids, ",")])
  out |> String.split() |> Enum.map(&String.to_integer/1) |> Enum.sum() |> div(1024)
end

pct = fn sorted, p -> Enum.at(sorted, min(length(sorted) - 1, trunc(p * length(sorted)))) end

for n_nodes <- [1, 2] do
  started = nodes.(n_nodes)
  pids = for {_, pid} <- started, do: to_string(pid)
  idle = rss.(pids)

  # a warm look on each node first, so a round measures looks and not the module's first load
  for {node, _} <- started, do: Look.look(node, "<p>warm</p>", base: "https://example.com/")

  for c <- [1, 8, 32, 64] do
    work = Stream.cycle(pages) |> Enum.take(per_round) |> Enum.with_index()
    peak = :counters.new(1, [])
    sampler = spawn(fn ->
      sample = fn sample ->
        :counters.put(peak, 1, max(:counters.get(peak, 1), rss.(pids)))
        receive do
          :stop -> :ok
        after
          50 -> sample.(sample)
        end
      end

      sample.(sample)
    end)

    t0 = System.monotonic_time(:microsecond)

    results =
      work
      |> Task.async_stream(
        fn {{kind, html, css, base}, i} ->
          {node, _} = Enum.at(started, rem(i, n_nodes))
          a = System.monotonic_time(:microsecond)
          r = Look.look(node, html, base: base, css: css, width: if(rem(i, 2) == 0, do: 390, else: 1280), timeout: 60_000)
          {kind, elem(r, 0), System.monotonic_time(:microsecond) - a}
        end,
        max_concurrency: c,
        timeout: 120_000
      )
      |> Enum.map(fn {:ok, r} -> r end)

    wall = (System.monotonic_time(:microsecond) - t0) / 1_000_000
    send(sampler, :stop)
    ms = results |> Enum.map(&div(elem(&1, 2), 1000)) |> Enum.sort()
    ok = Enum.count(results, &(elem(&1, 1) == :ok))
    rate = length(results) / wall

    IO.puts(
      "#{n_nodes} node(s), #{String.pad_leading("#{c}", 2)} at once: p50 #{pct.(ms, 0.5)} ms, p99 #{pct.(ms, 0.99)} ms, " <>
        "#{Float.round(rate, 1)} looks/s (#{Float.round(rate / System.schedulers_online(), 2)} a scheduler), " <>
        "#{ok}/#{length(results)} ok, memory #{idle} MB idle, #{:counters.get(peak, 1)} MB peak"
    )

    for {kind, rs} <- Enum.group_by(results, &elem(&1, 0)) |> Enum.sort(), c == 1 do
      kms = rs |> Enum.map(&div(elem(&1, 2), 1000)) |> Enum.sort()
      IO.puts("    #{kind}: p50 #{pct.(kms, 0.5)} ms, p99 #{pct.(kms, 0.99)} ms (#{length(rs)})")
    end
  end

  for {node, _} <- started, do: GenServer.stop(node)
end

# What a node's packs cost (Arock PROJECT.md §15 item 4), with the real Litestream:
#
#   mix run --no-start bench/packs.exs load <computers> <seconds> [every_ms]
#     wakes `computers` computers, each running a small command every `every_ms` (3000, jittered) for `seconds`,
#     with the node's own settings (Litestream every 5 s, a pack every 60 s), then puts them all to sleep. The
#     service is played in memory and counts every request by kind, so the requests a node makes an hour are
#     counted, not guessed.
#
#   mix run --no-start bench/packs.exs cuts <computers> <minutes> <cut_bytes>
#     the packer alone, without Litestream: every computer's replica gains a segment of `cut_bytes` each 5 s cut (the
#     100-computer load run measured about 40 KB), and a round runs each minute. For more computers than one Mac's
#     Litestream keeps up with (at 1,000 it held SQLite's lock past the 5 s busy timeout).
#
#   mix run --no-start bench/packs.exs restore [service]
#     one computer's hour of work (a command every 3 s, Litestream's cut every 5 s, a pack a minute: 60 packs),
#     run in compressed time, then the node's disk lost and the computer rebuilt from its packs when the node
#     starts. With `service`, through arock.ai with this node's token (keychain moss-node-token).
alias Moss.{Computer, Litestream, Objects}
alias Moss.Objects.{Ledger, Packer}

scratch = Path.join(System.tmp_dir!(), "moss-packs-#{System.unique_integer([:positive])}")
Application.put_env(:moss, :work_dir, Path.join(scratch, "work"))
Application.put_env(:moss, :local_objects, Path.join(scratch, "objects"))
Application.put_env(:moss, :replication, :litestream)
Application.put_env(:moss, :idle_ms, 3_600_000)
Application.put_env(:moss, :host_dir, Path.join(scratch, "host"))

# The service in memory: every request counted as {method, route}, its bodies kept so wakes and restores work.
:ets.new(:bench_store, [:named_table, :public])
:ets.new(:bench_count, [:named_table, :public])

count = fn conn ->
  {:ok, body, conn} = Plug.Conn.read_body(conn, length: 1_000_000_000)
  ["moss", route | _] = String.split(conn.request_path, "/", trim: true)
  :ets.update_counter(:bench_count, {conn.method, route}, 1, {{conn.method, route}, 0})
  :ets.update_counter(:bench_count, {:bytes, conn.method, route}, byte_size(body), {{:bytes, conn.method, route}, 0})
  key = conn.request_path
  list = fn prefix, field ->
    items = for {k, v} <- :ets.tab2list(:bench_store), String.starts_with?(k, prefix <> "/"),
                do: %{name: String.replace_prefix(k, prefix <> "/", ""), size: byte_size(v)}
    Plug.Conn.send_resp(conn, 200, Jason.encode!(%{field => Enum.sort_by(items, & &1.name)}))
  end

  case {conn.method, String.split(conn.request_path, "/", trim: true)} do
    {"GET", ["moss", "packs", _]} -> list.(key, :packs)
    {"GET", ["moss", "logs", _]} -> list.(key, :segments)
    {"PUT", _} -> :ets.insert(:bench_store, {key, body}) && Plug.Conn.send_resp(conn, 204, "")
    {"DELETE", _} -> :ets.delete(:bench_store, key) && Plug.Conn.send_resp(conn, 204, "")
    {"GET", _} ->
      case {:ets.lookup(:bench_store, key), Plug.Conn.get_req_header(conn, "range")} do
        {[], _} -> Plug.Conn.send_resp(conn, 404, "{}")
        {[{_, v}], []} -> Plug.Conn.send_resp(conn, 200, v)
        {[{_, v}], ["bytes=" <> r]} ->
          [a, b] = String.split(r, "-")
          a = String.to_integer(a)
          b = if b == "", do: byte_size(v) - 1, else: min(String.to_integer(b), byte_size(v) - 1)
          Plug.Conn.send_resp(conn, 206, binary_part(v, a, b - a + 1))
      end
  end
end

counts = fn ->
  for {{m, r}, n} <- :ets.tab2list(:bench_count), is_binary(m), into: %{}, do: {"#{m} #{r}", n}
end

reset = fn -> :ets.delete_all_objects(:bench_count) end
ms = fn t0 -> System.monotonic_time(:millisecond) - t0 end

case System.argv() do
  ["load", n, seconds | rest] ->
    n = String.to_integer(n)
    seconds = String.to_integer(seconds)
    every = String.to_integer(List.first(rest) || "3000")
    System.put_env("MOSS_NODE_TOKEN", "bench")
    System.put_env("MOSS_NODE", "bench")
    Application.put_env(:moss, :objects, :service)
    Application.put_env(:moss, :service_req_options, plug: count)
    Application.put_env(:moss, :litestream_sync, System.get_env("MOSS_BENCH_SYNC", "5s"))
    Application.put_env(:moss, :pack_ms, 60_000)
    {:ok, _} = Application.ensure_all_started(:moss)
    ids = for i <- 1..n, do: "bench-#{i}"

    t0 = System.monotonic_time(:millisecond)
    ids |> Task.async_stream(&Computer.run(&1, "mkdir -p notes"), max_concurrency: 32, timeout: :infinity) |> Stream.run()
    IO.puts("#{n} computers awake in #{ms.(t0)} ms; wakes: #{inspect(counts.())}")
    reset.()

    # each computer a command every `every` ms, jittered, for `seconds`
    deadline = System.monotonic_time(:millisecond) + seconds * 1000

    workers =
      for id <- ids do
        Task.async(fn ->
          Process.sleep(:rand.uniform(every))

          Stream.iterate(1, &(&1 + 1))
          |> Enum.reduce_while(0, fn k, runs ->
            if System.monotonic_time(:millisecond) > deadline do
              {:halt, runs}
            else
              Computer.run(id, "echo #{k} >> notes/log.txt")
              Process.sleep(div(every, 2) + :rand.uniform(every))
              {:cont, runs + 1}
            end
          end)
        end)
      end

    runs = workers |> Task.await_many(:infinity) |> Enum.sum()
    work = counts.()
    bytes = for {{:bytes, "PUT", "packs"}, b} <- :ets.tab2list(:bench_count), do: b
    IO.puts("#{runs} commands in #{seconds} s on #{n} computers: #{inspect(work)}, #{Enum.sum(bytes)} bytes of packs")
    puts = Map.get(work, "PUT packs", 0)

    IO.puts(
      "an hour at this rate: #{Float.round(puts * 3600 / seconds, 1)} pack writes " <>
        "(#{Float.round(Enum.sum(bytes) / max(puts, 1) / 1_048_576, 2)} MiB a pack)"
    )

    reset.()
    t1 = System.monotonic_time(:millisecond)
    ids |> Task.async_stream(&Computer.sleep/1, max_concurrency: 32, timeout: :infinity) |> Stream.run()
    slept = ms.(t1)
    {:ok, gc} = Packer.pack()
    IO.puts("all asleep in #{slept} ms, then a round deleted #{gc.deleted} packs: #{inspect(counts.())}")

  ["cuts", n, minutes, cut] ->
    {n, minutes, cut} = {String.to_integer(n), String.to_integer(minutes), String.to_integer(cut)}
    System.put_env("MOSS_NODE_TOKEN", "bench")
    System.put_env("MOSS_NODE", "bench")
    Application.put_env(:moss, :replication, :whole)
    Application.put_env(:moss, :objects, :service)
    Application.put_env(:moss, :service_req_options, plug: count)
    Application.put_env(:moss, :pack_ms, 3_600_000)
    {:ok, _} = Application.ensure_all_started(:moss)
    {:ok, _} = Packer.start_link()
    for i <- 1..n, do: Ledger.put_gen("cut-#{i}", 1, %{})
    t0 = System.monotonic_time(:millisecond)

    for m <- 1..minutes, c <- 1..12 do
      for i <- 1..n do
        file = Path.join([Litestream.replica_dir("cut-#{i}"), "ltx", "0", :io_lib.format("~16.16.0b-~16.16.0b.ltx", [m * 12 + c, m * 12 + c]) |> to_string()])
        File.mkdir_p!(Path.dirname(file))
        File.write!(file, :crypto.strong_rand_bytes(cut))
      end

      if c == 12, do: {:ok, _} = Packer.pack()
    end

    work = counts.()
    bytes = for {{:bytes, "PUT", "packs"}, b} <- :ets.tab2list(:bench_count), do: b
    puts = Map.get(work, "PUT packs", 0)

    IO.puts(
      "#{n} computers, #{minutes} minutes of #{cut}-byte cuts every 5 s (#{ms.(t0)} ms): #{inspect(work)}; " <>
        "an hour: #{div(puts * 60, minutes)} pack writes of #{Float.round(Enum.sum(bytes) / max(puts, 1) / 1_048_576, 1)} MiB"
    )

  ["restore" | rest] ->
    service = rest == ["service"]
    Application.put_env(:moss, :objects, if(service, do: :service, else: :local))
    # compressed time: the rounds wait, and the bench cuts and packs as a minute of the node would
    Application.put_env(:moss, :pack_ms, 3_600_000)
    Application.put_env(:moss, :litestream_sync, "1h")
    {:ok, _} = Application.ensure_all_started(:moss)
    id = "packs-hour-#{System.system_time(:millisecond)}"
    path = Path.join(Litestream.computers_dir(), id <> ".sqlite")
    Computer.run(id, "mkdir -p notes")
    t0 = System.monotonic_time(:millisecond)

    # an hour: 60 minutes of 12 cuts of 5 s, a command every 3 s (20 a minute)
    for minute <- 1..60 do
      for cut <- 1..12 do
        for k <- 1..2, (cut - 1) * 2 + k <= 20, do: Computer.run(id, "echo #{minute}-#{cut}-#{k} >> notes/log.txt")
        {:ok, _} = Litestream.sync(path)
      end

      {:ok, _} = Packer.pack()
    end

    packs = Ledger.packs()
    held = for {_, es} <- packs, e <- es, e["id"] == id, reduce: 0, do: (acc -> acc + e["length"])
    levels = for {_, es} <- packs, e <- es, e["id"] == id, reduce: %{} do
      acc -> Map.update(acc, hd(String.split(e["name"], "/")), e["length"], &(&1 + e["length"]))
    end

    IO.puts("an hour of work made in #{ms.(t0)} ms: #{map_size(packs)} packs, #{held} bytes of its segments " <>
      "(by level: #{inspect(levels)})")
    {:ok, before} = Objects.pack_list()

    # the disk lost: the computer was awake and is gone from the node, with everything beside it
    DynamicSupervisor.terminate_child(Moss.Computer.Supervisor, Computer.whereis(id))
    Supervisor.terminate_child(Moss.Supervisor, Packer)
    Supervisor.terminate_child(Moss.Supervisor, Litestream)
    File.rm_rf!(Application.get_env(:moss, :work_dir))
    t1 = System.monotonic_time(:millisecond)
    {:ok, _} = Supervisor.restart_child(Moss.Supervisor, Litestream)
    {:ok, _} = Supervisor.restart_child(Moss.Supervisor, Packer)
    restored = ms.(t1)
    %{out: out} = Computer.run(id, "cat notes/log.txt")
    lines = length(String.split(out, "\n", trim: true))
    IO.puts("rebuilt from #{map_size(before)} packs in #{restored} ms (the node's start); #{lines} of 1200 lines back")
    :ok = Computer.sleep(id)
    {:ok, gc} = Packer.pack()
    :ok = Objects.delete(Objects.computer_key(id))
    IO.puts("asleep, and #{gc.deleted} packs deleted")
end

# the app's Litestream goes with it (a port's program outlives a BEAM that halts)
Application.stop(:moss)
File.rm_rf!(scratch)

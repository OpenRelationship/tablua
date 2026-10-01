# How many computers one node holds, and what each costs: `mix run bench/computers.exs [awake] [programs]`.
# It wakes `awake` computers (1000) on fresh disks and runs a shell command on each, then puts them all to
# sleep and wakes a sample again from their files, then runs `programs` (200) Python and Lua programs across
# the computers, a core's worth at a time. Memory counts each disk's SQLite connection as well as the BEAM. Disks go to a scratch directory, never to R2.
alias Moss.Computer

{awake, programs} =
  case System.argv() do
    [a, p | _] -> {String.to_integer(a), String.to_integer(p)}
    [a] -> {String.to_integer(a), 200}
    [] -> {1000, 200}
  end

scratch = Path.join(System.tmp_dir!(), "moss-bench-#{System.unique_integer([:positive])}")
Application.put_env(:moss, :objects, :local)
Application.put_env(:moss, :local_objects, Path.join(scratch, "objects"))
Application.put_env(:moss, :work_dir, Path.join(scratch, "work"))
Application.put_env(:moss, :idle_ms, 3_600_000)

# Memory is the node's physical footprint on macOS (`footprint`, which counts pages the OS has compressed or
# swapped, where ps's resident size drops under pressure) and its resident size elsewhere.
rss_mb = fn ->
  case System.find_executable("footprint") &&
         System.cmd("footprint", ["-p", System.pid()], stderr_to_stdout: true) do
    {out, 0} ->
      [_, n, unit] = Regex.run(~r/Footprint: ([\d.]+) (KB|MB|GB)/, out)

      String.to_float(if String.contains?(n, "."), do: n, else: n <> ".0") *
        %{"KB" => 1 / 1024, "MB" => 1, "GB" => 1024}[unit]

    _ ->
      {out, 0} = System.cmd("ps", ["-o", "rss=", "-p", System.pid()])
      String.to_integer(String.trim(out)) / 1024
  end
end

settle = fn -> for _ <- 1..3, do: :erlang.garbage_collect() end

pct = fn xs, p ->
  s = Enum.sort(xs)
  Enum.at(s, min(length(s) - 1, round(p / 100 * (length(s) - 1))))
end

ms = fn f ->
  t = System.monotonic_time(:microsecond)
  r = f.()
  {(System.monotonic_time(:microsecond) - t) / 1000, r}
end

line = fn label, xs ->
  IO.puts(
    "#{label}: p50 #{Float.round(pct.(xs, 50), 1)} ms, p95 #{Float.round(pct.(xs, 95), 1)} ms (#{length(xs)})"
  )
end

ids = for i <- 1..awake, do: "bench-#{i}"
cores = System.schedulers_online()

# The programs compile once per node; the first run of each pays for it, so it happens before anything is timed.
{warm, _} =
  ms.(fn ->
    Computer.run("bench-warm", "python -c 'print(1)' && lua -e 'print(1)'")
    Computer.sleep("bench-warm")
  end)

IO.puts("node: #{cores} schedulers; programs ready in #{round(warm)} ms")
# One at a time first: a new computer's wake and first command with nothing else running.
alone =
  for i <- 1..50 do
    {t, %{code: 0}} = ms.(fn -> Computer.run("bench-alone-#{i}", "echo hi > /home/a.txt") end)
    Computer.sleep("bench-alone-#{i}")
    t
  end

line.("new computer alone, first command", alone)
settle.()
base = rss_mb.()
beam = :erlang.memory(:total) / 1_048_576
IO.puts("node at rest: #{Float.round(base, 1)} MB (BEAM #{Float.round(beam, 1)} MB)")

# 1. Awake: each computer wakes on a new disk and runs a shell command that writes and reads a file.
wakes =
  ids
  |> Task.async_stream(
    fn id ->
      {t, %{code: 0}} =
        ms.(fn ->
          Computer.run(id, "echo 'water the fern' > /home/todo.txt && cat /home/todo.txt")
        end)

      t
    end,
    max_concurrency: cores * 4,
    timeout: :infinity
  )
  |> Enum.map(fn {:ok, t} -> t end)

line.("new computer, first command", wakes)
settle.()
up = rss_mb.()
beam_up = :erlang.memory(:total) / 1_048_576

IO.puts(
  "#{awake} awake: #{Float.round(up, 1)} MB, #{Float.round((up - base) * 1024 / awake, 1)} KB each (BEAM #{Float.round((beam_up - beam) * 1024 / awake, 1)} KB each)"
)

# 2. Asleep: each computer is its file in the object store, and nothing on the node.
{t_sleep, _} = ms.(fn -> Enum.each(ids, &Computer.sleep/1) end)
settle.()
down = rss_mb.()
files = Path.wildcard(Path.join([scratch, "objects", "computers", "bench-*.sqlite"]))
bytes = files |> Enum.map(&File.stat!(&1).size) |> Enum.sum()

IO.puts(
  "all asleep in #{round(t_sleep)} ms: #{Float.round(down, 1)} MB; a sleeping disk is #{round(bytes / max(length(files), 1) / 1024)} KB"
)

# 3. Waking from its file: the command an agent sends to a sleeping computer.
sample = Enum.take_every(ids, max(div(awake, 200), 1))

rewakes =
  for id <- sample do
    {t, %{out: "water the fern\n"}} = ms.(fn -> Computer.run(id, "cat /home/todo.txt") end)
    t
  end

line.("sleeping computer, wake and command", rewakes)

# 4. Programs: Python and Lua runs spread over the awake sample, a core's worth at a time.
jobs =
  for i <- 1..programs do
    id = Enum.at(sample, rem(i, length(sample)))

    if rem(i, 2) == 0,
      do: {:python, id, "python -c 'print(sum(i * i for i in range(10000)))'"},
      else: {:lua, id, "lua -e 'local s = 0 for i = 1, 10000 do s = s + i * i end print(s)'"}
  end

peak = :counters.new(1, [])

watcher =
  spawn(fn ->
    Stream.repeatedly(fn ->
      Process.sleep(50)
      rss_mb.()
    end)
    |> Enum.each(fn mb ->
      if mb > :counters.get(peak, 1), do: :counters.put(peak, 1, round(mb))
    end)
  end)

{t_programs, runs} =
  ms.(fn ->
    jobs
    |> Task.async_stream(
      fn {kind, id, cmd} ->
        {t, %{code: 0}} = ms.(fn -> Computer.run(id, cmd) end)
        {kind, t}
      end,
      max_concurrency: cores,
      timeout: :infinity
    )
    |> Enum.map(fn {:ok, r} -> r end)
  end)

Process.exit(watcher, :kill)

for kind <- [:python, :lua] do
  line.("#{kind} program", for({^kind, t} <- runs, do: t))
end

IO.puts(
  "#{programs} programs in #{round(t_programs)} ms: #{Float.round(programs / (t_programs / 1000), 1)} a second; peak #{:counters.get(peak, 1)} MB"
)

Enum.each(sample, &Computer.sleep/1)
File.rm_rf!(scratch)

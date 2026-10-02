defmodule Moss.ReplicationTest do
  # Arock's PROJECT.md §15 item 4: an awake computer's file is streamed by Litestream to the node's replica and its
  # recent work packed once a round; it sleeps as its whole file and wakes from it; a node that lost its disk
  # rebuilds the computers that were awake from its packs; and a computer that slept as its log before packs wakes
  # from it. Runs where the litestream binary is (tag :litestream, test_helper.exs); with --only service, through
  # arock.ai with this node's token. Prints what it measured.
  use ExUnit.Case, async: false

  alias Moss.{Computer, Litestream, Objects}
  alias Moss.Objects.{Ledger, Packer, Snapshot}

  @moduletag :litestream

  setup ctx do
    work = Path.join(System.tmp_dir!(), "moss-ls-#{System.unique_integer([:positive])}")
    keys = [:work_dir, :local_objects, :objects, :replication, :pack_ms]
    before = Map.new(keys, &{&1, Application.get_env(:moss, &1)})
    Application.put_env(:moss, :work_dir, Path.join(work, "work"))
    Application.put_env(:moss, :local_objects, Path.join(work, "objects"))
    Application.put_env(:moss, :objects, if(ctx[:service], do: :service, else: :local))
    Application.put_env(:moss, :replication, :litestream)
    # a test that packs when it says waits for no round
    if ctx[:manual], do: Application.put_env(:moss, :pack_ms, 3_600_000)

    on_exit(fn ->
      for {k, v} <- before,
          do:
            if(v == nil,
              do: Application.delete_env(:moss, k),
              else: Application.put_env(:moss, k, v)
            )

      File.rm_rf!(work)
    end)

    start_supervised!(Litestream)
    start_supervised!(Packer)
    :ok
  end

  defp id(prefix), do: "#{prefix}-#{System.system_time(:millisecond)}"
  defp ms(t0), do: System.monotonic_time(:millisecond) - t0
  defp path(id), do: Path.join(Litestream.computers_dir(), id <> ".sqlite")

  defp sleep!(id) do
    ref = Process.monitor(Computer.whereis(id))
    assert :ok = Computer.sleep(id)
    assert_receive {:DOWN, ^ref, :process, _, :normal}, 30_000
  end

  # everything the computer wrote, in its replica and then in a pack
  defp packed!(id) do
    {:ok, _} = Litestream.sync(path(id))
    assert {:ok, _} = Packer.pack()
  end

  defp snapshot_gen(id) do
    {:ok, body} = Objects.get(Objects.computer_key(id))
    Snapshot.gen_of(body)
  end

  # how long until a round has packed the computer's newest work: the rounds run every pack_ms on their own
  defp packed_after(id, before, t0) do
    now = (Ledger.gen(id) || %{})["packed"] || %{}

    cond do
      map_size(now) > map_size(before) -> ms(t0)
      ms(t0) > 15_000 -> flunk("nothing packed in 15 s")
      true -> Process.sleep(20) && packed_after(id, before, t0)
    end
  end

  defp events(id) do
    {:ok, [%{"n" => n}]} =
      Moss.Db.exec(
        :sys.get_state(Computer.whereis(id)).disk.conn,
        "select count(*) as n from events where keyword = 'Run Command'",
        []
      )

    n
  end

  defp round_trip(id) do
    # a typical computer: a few notes, a Lua tool and its run, then 200 KB of data written in one file
    Computer.run(id, "mkdir -p notes && echo 'water the fern' > notes/todo.txt")
    Computer.run(id, ~S|echo 'print(#fs.read("notes/todo.txt"))' > count.lua && lua count.lua|)
    data = Base.encode64(:crypto.strong_rand_bytes(150_000))
    assert :ok = GenServer.call(Computer.whereis(id), {:files, "/home", %{"data.txt" => data}})

    # the everyday case: a small command, and how long until a pack holds it (Litestream's sync, then a round)
    delays =
      for n <- 1..3 do
        before = Ledger.gen(id)["packed"]
        t0 = System.monotonic_time(:millisecond)
        Computer.run(id, "echo #{n} >> notes/log.txt")
        packed_after(id, before, t0)
      end

    t1 = System.monotonic_time(:millisecond)
    sleep!(id)
    slept = ms(t1)
    refute File.exists?(path(id))
    refute File.exists?(Litestream.replica_dir(id))
    assert snapshot_gen(id) == 1
    {:ok, snapshot} = Objects.get(Objects.computer_key(id))

    t2 = System.monotonic_time(:millisecond)
    assert %{out: "water the fern\n"} = Computer.run(id, "cat notes/todo.txt")
    woke = ms(t2)
    assert %{out: ^data} = Computer.run(id, "cat data.txt")
    assert %{out: out} = Computer.run(id, "lua count.lua")
    assert out =~ "15"
    # the log came back too: the runs before the sleep are events
    assert events(id) >= 5

    # the next wake is the next chain, and keeps the newer write
    Computer.run(id, "echo again >> notes/todo.txt")
    sleep!(id)
    assert snapshot_gen(id) == 2
    assert %{out: "water the fern\nagain\n"} = Computer.run(id, "cat notes/todo.txt")
    sleep!(id)
    # every computer in the packs is asleep on a later chain: a round collects them all
    assert {:ok, _} = Packer.pack()
    assert Ledger.packs() == %{}

    IO.puts(
      "\n#{id}: a small command packed after #{inspect(delays)} ms; sleep #{slept} ms " <>
        "(a #{byte_size(snapshot)}-byte snapshot, one write); wake #{woke} ms (one read)"
    )

    id
  end

  test "a computer sleeps as its whole file and wakes from it, a new chain each wake" do
    round_trip(id("ls"))
  end

  defp lose_disk!(ids) do
    for id <- ids,
        pid = Computer.whereis(id),
        do: DynamicSupervisor.terminate_child(Moss.Computer.Supervisor, pid)

    stop_supervised!(Packer)
    stop_supervised!(Litestream)
    gone!(Application.get_env(:moss, :work_dir), 100)
  end

  # Litestream may still be writing its last sync as it exits
  defp gone!(dir, 0), do: File.rm_rf!(dir)

  defp gone!(dir, n) do
    with {:error, _, _} <- File.rm_rf(dir) do
      Process.sleep(20)
      gone!(dir, n - 1)
    end
  end

  defp loss(id) do
    # a sleeping neighbour's packs say nothing it must be rebuilt from
    other = id <> "-asleep"
    Computer.run(other, "echo asleep > a.txt")
    packed!(other)
    sleep!(other)

    Computer.run(id, "mkdir -p notes && echo 'before the loss' > notes/a.txt")
    data = Base.encode64(:crypto.strong_rand_bytes(60_000))
    assert :ok = GenServer.call(Computer.whereis(id), {:files, "/home", %{"data.txt" => data}})
    for n <- 1..5, do: Computer.run(id, "echo #{n} >> notes/log.txt")
    packed!(id)
    runs = events(id)
    # written after the last pack: a lost disk loses it
    Computer.run(id, "echo 'after the last pack' > notes/b.txt")

    lose_disk!([id])
    t0 = System.monotonic_time(:millisecond)
    start_supervised!(Litestream)
    start_supervised!(Packer)
    restored = ms(t0)

    assert Ledger.slept(id) == 1
    assert %{out: "before the loss\n"} = Computer.run(id, "cat notes/a.txt")
    assert %{out: ^data} = Computer.run(id, "cat data.txt")
    assert %{out: "1\n2\n3\n4\n5\n"} = Computer.run(id, "cat notes/log.txt")
    assert %{code: 1} = Computer.run(id, "cat notes/b.txt")
    # its runs up to the last pack, and the four just above
    assert events(id) == runs + 4
    assert %{out: "asleep\n"} = Computer.run(other, "cat a.txt")
    sleep!(id)
    sleep!(other)
    assert {:ok, %{deleted: n}} = Packer.pack()
    assert n > 0
    assert Ledger.packs() == %{}

    IO.puts(
      "\n#{id}: rebuilt from its packs after a lost disk, the node started in #{restored} ms"
    )

    id
  end

  @tag :manual
  test "a node that lost its disk rebuilds the computers that were awake from its packs" do
    loss(id("ls-loss"))
  end

  # A computer awake for days never sleeps, so nothing outgrows its packs. Every snapshot_ms awake (a few hours) its
  # whole file goes to the store, ending its chain: the packs of that chain are deleted, and its work goes on as
  # the next chain, which a lost disk rebuilds on top of nothing but its own packs.
  @tag :manual
  test "a computer awake a long time is snapshotted, so its old packs are deleted" do
    id = id("ls-awake")
    Computer.run(id, "mkdir -p notes && echo 'before the snapshot' > notes/a.txt")
    for n <- 1..3, do: Computer.run(id, "echo #{n} >> notes/log.txt")
    packed!(id)
    assert [_ | _] = Map.keys(Ledger.packs())

    t0 = System.monotonic_time(:millisecond)
    assert :ok = Computer.snapshot(id)
    took = ms(t0)
    assert snapshot_gen(id) == 1
    assert %{"gen" => 2} = Ledger.gen(id)
    assert File.exists?(path(id))

    # still awake, still streamed: its next work is packed as the next chain, and the old chain's packs are gone
    Computer.run(id, "echo 'after the snapshot' > notes/b.txt")
    packed!(id)
    chains = for {_, es} <- Ledger.packs(), c <- Ledger.chains(es), uniq: true, do: c
    assert chains == [{id, 2}]

    lose_disk!([id])
    start_supervised!(Litestream)
    start_supervised!(Packer)
    assert %{out: "before the snapshot\n"} = Computer.run(id, "cat notes/a.txt")
    assert %{out: "1\n2\n3\n"} = Computer.run(id, "cat notes/log.txt")
    assert %{out: "after the snapshot\n"} = Computer.run(id, "cat notes/b.txt")
    sleep!(id)
    assert {:ok, _} = Packer.pack()
    assert Ledger.packs() == %{}

    IO.puts(
      "\n#{id}: snapshotted awake in #{took} ms; its old packs deleted, its work rebuilt across the cut"
    )
  end

  test "a computer that slept as its log before packs wakes from it, and sleeps whole after" do
    c = id("ls-old")
    Computer.run(c, "echo old > old.txt")
    {:ok, _} = Litestream.sync(path(c))
    # its segments where the old shipper put them, and nothing else of it anywhere
    ltx = Path.join(Litestream.replica_dir(c), "ltx")

    for f <- Path.wildcard(Path.join(ltx, "*/*.ltx")) do
      dest =
        Path.join([
          Application.get_env(:moss, :local_objects),
          "logs",
          c,
          Path.relative_to(f, ltx)
        ])

      File.mkdir_p!(Path.dirname(dest))
      File.cp!(f, dest)
    end

    lose_disk!([c])
    start_supervised!(Litestream)
    start_supervised!(Packer)
    assert Objects.get(Objects.computer_key(c)) == :not_found
    assert %{out: "old\n"} = Computer.run(c, "cat old.txt")
    sleep!(c)
    assert snapshot_gen(c) == 1
    assert %{out: "old\n"} = Computer.run(c, "cat old.txt")
  end

  test "a computer kept whole before Litestream wakes from its whole file, then streams" do
    c = id("ls-whole")
    Application.put_env(:moss, :replication, :whole)
    Computer.run(c, "echo old > old.txt")
    sleep!(c)
    assert snapshot_gen(c) == 0
    Application.put_env(:moss, :replication, :litestream)
    assert %{out: "old\n"} = Computer.run(c, "cat old.txt")
    sleep!(c)
    assert snapshot_gen(c) == 1
  end

  test "one Litestream per work dir: a BEAM that borrows it starts none, and a second node is refused" do
    Application.put_env(:moss, :litestream_run, false)
    assert Litestream.init([]) == :ignore
    assert Packer.init([]) == :ignore
    Application.delete_env(:moss, :litestream_run)

    # another BEAM's Litestream: its parent is alive and is not this BEAM's
    dir = Path.join(Application.get_env(:moss, :work_dir), "other")
    File.mkdir_p!(Path.join(dir, "computers"))
    config = Path.join(dir, "litestream.yml")
    File.write!(config, Litestream.litestream_config(dir))
    line = "#{Litestream.bin()} replicate -no-expand-env -config '#{config}' & echo $!; wait"
    port = Port.open({:spawn_executable, "/bin/sh"}, [:binary, {:args, ["-c", line]}, {:cd, dir}])
    assert_receive {^port, {:data, pid}}, 5_000
    File.write!(Path.join(dir, "litestream.pid"), String.trim(pid))
    Application.put_env(:moss, :work_dir, dir)

    try do
      assert {:stop, why} = Litestream.init([])
      assert why =~ "is already streamed by the Litestream (pid #{String.trim(pid)})"
    after
      System.cmd("kill", [String.trim(pid)])
    end
  end

  # Through arock.ai with this node's token (keychain moss-node-token): `mix test --only service`.
  @tag :service
  test "a computer sleeps and wakes through the service" do
    c = round_trip(id("ls-probe"))
    assert :ok = Objects.delete(Objects.computer_key(c))
  end

  @tag :service
  @tag :manual
  test "a computer is rebuilt from its packs through the service" do
    c = loss(id("ls-probe-loss"))
    assert :ok = Objects.delete(Objects.computer_key(c))
    assert :ok = Objects.delete(Objects.computer_key(c <> "-asleep"))
  end
end

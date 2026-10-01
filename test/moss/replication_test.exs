defmodule Moss.ReplicationTest do
  # Arock's PROJECT.md §14.7 goal 6, §15.4: an awake computer's file is streamed by Litestream to the node's file
  # replica, the shipper sends its segments to the store, and a computer whose file is gone wakes from its segments
  # alone. Runs where the litestream binary is (tag :litestream, test_helper.exs); with --only service, through
  # arock.ai with this node's token. Prints what it measured.
  use ExUnit.Case, async: false

  alias Moss.{Computer, Litestream, Objects}
  alias Moss.Objects.Shipper

  @moduletag :litestream

  setup ctx do
    work = Path.join(System.tmp_dir!(), "moss-ls-#{System.unique_integer([:positive])}")
    keys = [:work_dir, :local_objects, :objects, :replication]
    before = Map.new(keys, &{&1, Application.get_env(:moss, &1)})
    Application.put_env(:moss, :work_dir, Path.join(work, "work"))
    Application.put_env(:moss, :local_objects, Path.join(work, "objects"))
    Application.put_env(:moss, :objects, if(ctx[:service], do: :service, else: :local))
    Application.put_env(:moss, :replication, :litestream)

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
    start_supervised!(Shipper)
    :ok
  end

  defp id(prefix), do: "#{prefix}-#{System.system_time(:millisecond)}"
  defp ms(t0), do: System.monotonic_time(:millisecond) - t0

  defp sleep!(id) do
    ref = Process.monitor(Computer.whereis(id))
    assert :ok = Computer.sleep(id)
    assert_receive {:DOWN, ^ref, :process, _, :normal}, 30_000
  end

  # how long until the store lists more of the computer's segments than `before`
  defp shipped_after(id, before, t0) do
    {:ok, now} = Objects.log_list(id)

    cond do
      map_size(now) > map_size(before) -> {ms(t0), now}
      ms(t0) > 15_000 -> flunk("nothing shipped in 15 s")
      true -> Process.sleep(20) && shipped_after(id, before, t0)
    end
  end

  defp round_trip(id) do
    # a typical computer: a few notes, a Lua tool and its run, then 200 KB of data written in one file
    Computer.run(id, "mkdir -p notes && echo 'water the fern' > notes/todo.txt")
    Computer.run(id, ~S|echo 'print(#fs.read("notes/todo.txt"))' > count.lua && lua count.lua|)
    {:ok, before} = Objects.log_list(id)
    t0 = System.monotonic_time(:millisecond)
    data = Base.encode64(:crypto.strong_rand_bytes(150_000))
    assert :ok = GenServer.call(Computer.whereis(id), {:files, "/home", %{"data.txt" => data}})
    {first_delay, first} = shipped_after(id, before, t0)
    [snapshot] = Map.values(Map.drop(first, Map.keys(before)))

    # then the everyday case: a small command, its segment and how long until the store has it
    small =
      for n <- 1..5 do
        {:ok, before} = Objects.log_list(id)
        t0 = System.monotonic_time(:millisecond)
        Computer.run(id, "echo #{n} >> notes/log.txt")
        {delay, now} = shipped_after(id, before, t0)
        {delay, Enum.sum(Map.values(Map.drop(now, Map.keys(before))))}
      end

    t1 = System.monotonic_time(:millisecond)
    sleep!(id)
    slept = ms(t1)
    path = Path.join([Application.get_env(:moss, :work_dir), "computers", id <> ".sqlite"])
    refute File.exists?(path)
    refute File.exists?(Litestream.replica_dir(id))
    # no whole file: the computer is its log
    assert Objects.get(Objects.computer_key(id)) == :not_found
    {:ok, stored} = Objects.log_list(id)

    t2 = System.monotonic_time(:millisecond)
    assert %{out: "water the fern\n"} = Computer.run(id, "cat notes/todo.txt")
    woke = ms(t2)
    assert %{out: ^data} = Computer.run(id, "cat data.txt")
    assert %{out: out} = Computer.run(id, "lua count.lua")
    assert out =~ "15"

    # the log came back too: the runs before the sleep are events
    {:ok, rows} =
      Moss.Db.exec(
        :sys.get_state(Computer.whereis(id)).disk.conn,
        "select count(*) as n from events where keyword = 'Run Command'",
        []
      )

    assert [%{"n" => n}] = rows
    assert n >= 2

    # and it streams on after a wake: a second sleep and wake keeps the newer write
    Computer.run(id, "echo again >> notes/todo.txt")
    sleep!(id)
    assert %{out: "water the fern\nagain\n"} = Computer.run(id, "cat notes/todo.txt")
    sleep!(id)

    {delays, sizes} = Enum.unzip(small)

    IO.puts(
      "\n#{id}: 200 KB written, shipped in #{first_delay} ms as a #{snapshot}-byte segment; " <>
        "a small command shipped in #{inspect(delays)} ms as segments of #{inspect(sizes)} bytes; " <>
        "sleep #{slept} ms; wake from #{map_size(stored)} segments (#{Enum.sum(Map.values(stored))} bytes) #{woke} ms"
    )

    id
  end

  test "a computer whose file is gone wakes from its log's segments alone" do
    round_trip(id("ls"))
  end

  test "a computer kept whole before Litestream wakes from its whole file, then streams" do
    c = id("ls-whole")
    Application.put_env(:moss, :replication, :whole)
    Computer.run(c, "echo old > old.txt")
    sleep!(c)
    assert {:ok, _} = Objects.get(Objects.computer_key(c))
    Application.put_env(:moss, :replication, :litestream)
    assert %{out: "old\n"} = Computer.run(c, "cat old.txt")
    sleep!(c)
    assert {:ok, segments} = Objects.log_list(c)
    assert map_size(segments) > 0
  end

  test "one Litestream per work dir: a BEAM that borrows it starts none, and a second node is refused" do
    Application.put_env(:moss, :litestream_run, false)
    assert Litestream.init([]) == :ignore
    assert Shipper.init([]) == :ignore
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
  test "a computer's log round-trips through the service" do
    c = round_trip(id("ls-probe"))
    {:ok, segments} = Objects.log_list(c)
    for {name, _} <- segments, do: assert(:ok = Objects.log_delete(c, name))
    assert {:ok, %{}} = Objects.log_list(c)
  end
end

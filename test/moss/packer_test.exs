defmodule Moss.PackerTest do
  # Arock's PROJECT.md §15 item 4: once a round, the node puts every awake computer's new segments in one pack
  # through the service, under its own name; a pack every computer in it has outgrown is deleted; and a node
  # starting learns the packs it does not know from their headers. Litestream itself is not needed here: the
  # replica's files are written by hand (replication_test.exs runs the real one, and the rebuild from packs).
  use ExUnit.Case, async: false

  alias Moss.{Litestream, Objects}
  alias Moss.Objects.{Ledger, Lock, Pack, Packer, Recover}

  @a "0/0000000000000001-0000000000000001.ltx"
  @b "0/0000000000000002-0000000000000002.ltx"

  setup do
    work = Path.join(System.tmp_dir!(), "moss-packer-#{System.unique_integer([:positive])}")
    keys = [:work_dir, :objects, :pack_ms, :pack_bytes]
    before = Map.new(keys, &{&1, Application.get_env(:moss, &1)})
    Application.put_env(:moss, :work_dir, work)
    Application.put_env(:moss, :objects, :service)
    # the rounds wait; each test packs when it says
    Application.put_env(:moss, :pack_ms, 3_600_000)
    System.put_env("MOSS_NODE_TOKEN", "node-token-test")
    System.put_env("MOSS_NODE", "node-test")
    {:ok, store} = Agent.start_link(fn -> %{} end)
    {:ok, refusing} = Agent.start_link(fn -> false end)

    refuse = fn method, path ->
      Agent.get(refusing, & &1) and method == "PUT" and path =~ "/packs/"
    end

    Application.put_env(:moss, :service_req_options,
      plug: Moss.FakeService.plug(self(), store: store, refuse: refuse)
    )

    on_exit(fn ->
      for {k, v} <- before,
          do:
            if(v == nil,
              do: Application.delete_env(:moss, k),
              else: Application.put_env(:moss, k, v)
            )

      System.delete_env("MOSS_NODE_TOKEN")
      System.delete_env("MOSS_NODE")
      Application.delete_env(:moss, :service_req_options)
      File.rm_rf!(work)
    end)

    %{store: store, refusing: refusing}
  end

  defp segment(id, name, body) do
    file = Path.join([Litestream.replica_dir(id), "ltx", name])
    File.mkdir_p!(Path.dirname(file))
    File.write!(file, body)
  end

  defp awake(id, gen), do: Ledger.put_gen(id, gen, %{})

  defp asked(method) do
    receive do
      {:asked, ^method, "/moss/packs/" <> rest, _} -> [rest | asked(method)]
      {:asked, _, _, _} -> asked(method)
    after
      0 -> []
    end
  end

  defp entries(store, path) do
    ["node-test", name] = String.split(path, "/")
    {:ok, entries} = Pack.header(Agent.get(store, &Map.fetch!(&1, {:pack, "node-test", name})))
    entries
  end

  test "one round puts every awake computer's new segments in one pack; nothing new puts nothing",
       %{store: store} do
    start_supervised!(Packer)

    for id <- ["rock-1", "rock-2", "rock-3"] do
      awake(id, 1)
      segment(id, @a, "one " <> id)
    end

    assert {:ok, %{packs: 1, computers: 3}} = Packer.pack()
    assert [path] = asked("PUT")
    assert Enum.map(entries(store, path), & &1["id"]) == ["rock-1", "rock-2", "rock-3"]

    assert {:ok, %{packs: 0}} = Packer.pack()
    assert asked("PUT") == []

    segment("rock-2", @b, "two")
    assert {:ok, %{packs: 1, computers: 1}} = Packer.pack()
    assert [path] = asked("PUT")
    assert [%{"id" => "rock-2", "name" => @b, "gen" => 1}] = entries(store, path)
  end

  test "a computer not awake here is not packed, and one another process holds waits for the next round" do
    start_supervised!(Packer)
    segment("rock-4", @a, "no chain on this node")
    awake("rock-5", 2)
    segment("rock-5", @a, "held")
    :ok = Lock.take("rock-5", 0)
    assert {:ok, %{packs: 0}} = Packer.pack()
    Lock.release("rock-5")
    assert {:ok, %{packs: 1, computers: 1}} = Packer.pack()
    assert %{"gen" => 2, "packed" => %{@a => 4}} = Ledger.gen("rock-5")
  end

  test "a pack that fails to go up marks nothing, and the next round sends it all", %{
    refusing: refusing
  } do
    start_supervised!(Packer)
    awake("rock-6", 1)
    segment("rock-6", @a, "one")
    Agent.update(refusing, fn _ -> true end)
    assert {:error, why} = Packer.pack()
    assert why =~ "500"
    assert %{"packed" => packed} = Ledger.gen("rock-6")
    assert packed == %{}
    assert Ledger.packs() == %{}
    Agent.update(refusing, fn _ -> false end)
    assert {:ok, %{packs: 1}} = Packer.pack()
    assert %{"packed" => %{@a => 3}} = Ledger.gen("rock-6")
  end

  test "a round larger than a pack writes several, and a computer's chain reads back whole across them" do
    Application.put_env(:moss, :pack_bytes, 8)
    start_supervised!(Packer)
    big = :crypto.strong_rand_bytes(20)
    awake("rock-7", 3)
    segment("rock-7", @a, big)
    segment("rock-7", @b, "two")
    assert {:ok, %{packs: 3}} = Packer.pack()
    assert {:ok, %{@a => ^big, @b => "two"}} = Recover.segments("rock-7", 3)
    assert {:ok, other} = Recover.segments("rock-7", 2)
    assert other == %{}
  end

  test "a pack is deleted once every computer in it slept on that chain or a later one" do
    start_supervised!(Packer)
    awake("rock-8", 1)
    segment("rock-8", @a, "a")
    awake("rock-9", 4)
    segment("rock-9", @a, "b")
    assert {:ok, _} = Packer.pack()
    asked("PUT")
    Ledger.put_slept("rock-8", 1)
    Ledger.put_slept("rock-9", 3)
    assert Packer.collect() == 0
    Ledger.put_slept("rock-9", 4)
    assert Packer.collect() == 1
    assert [_] = asked("DELETE")
    assert Ledger.packs() == %{}
    # no pack needs their sleeps any more
    assert Ledger.slept_ids() == []
  end

  test "a node starting learns the packs its ledger does not know from their headers", %{
    store: store
  } do
    {bytes, _} = Pack.encode(hd(Pack.plan([%{id: "rock-10", gen: 1, name: @a, body: "x"}], 100)))
    name = Pack.name()
    Agent.update(store, &Map.put(&1, {:pack, "node-test", name}, bytes))
    # rock-10's file is on the node: awake here, nothing to rebuild
    File.mkdir_p!(Litestream.computers_dir())
    File.write!(Path.join(Litestream.computers_dir(), "rock-10.sqlite"), "")
    start_supervised!(Packer)
    assert %{^name => [%{"id" => "rock-10", "gen" => 1}]} = Ledger.packs()
  end

  test "a fresh node whose packs hold a computer that slept after them rebuilds nothing, and collects them",
       %{store: store} do
    {bytes, _} = Pack.encode(hd(Pack.plan([%{id: "rock-11", gen: 2, name: @a, body: "x"}], 100)))
    Agent.update(store, &Map.put(&1, {:pack, "node-test", Pack.name()}, bytes))

    snapshot =
      "SQLite format 3" <>
        <<0>> <> :binary.copy(<<0>>, 44) <> <<2::32>> <> :binary.copy(<<0>>, 36)

    :ok = Objects.put(Objects.computer_key("rock-11"), snapshot)
    start_supervised!(Packer)
    assert Ledger.slept("rock-11") == 2
    assert {:ok, %{deleted: 1}} = Packer.pack()
    assert {:ok, %{}} = Objects.pack_list()
  end

  test "a work dir new to the store does not start when it cannot list its packs", %{
    refusing: refusing
  } do
    Application.put_env(:moss, :service_req_options,
      plug: Moss.FakeService.plug(self(), refuse: fn m, p -> m == "GET" and p =~ "/packs/" end)
    )

    _ = refusing
    assert {:stop, why} = Packer.init([])
    assert why =~ "nothing may wake"
  end
end

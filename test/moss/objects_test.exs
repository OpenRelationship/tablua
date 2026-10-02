defmodule Moss.ObjectsTest do
  use ExUnit.Case, async: false

  alias Moss.Objects.{Local, Service}

  test "the local store puts, gets and deletes, and a missing key is not found" do
    key = "probe/#{System.unique_integer([:positive])}.bin"
    assert Local.get(key) == :not_found
    assert :ok = Local.put(key, <<0, 1, 2, 255>>)
    assert Local.get(key) == {:ok, <<0, 1, 2, 255>>}
    assert :ok = Local.delete(key)
    assert Local.get(key) == :not_found
    assert :ok = Local.delete(key)
  end

  setup do
    {:ok, store} = Agent.start_link(fn -> %{} end)
    System.put_env("MOSS_NODE_TOKEN", "node-token-test")
    System.put_env("MOSS_NODE", "node-test")

    Application.put_env(:moss, :service_req_options,
      plug: Moss.FakeService.plug(self(), store: store)
    )

    on_exit(fn ->
      System.delete_env("MOSS_NODE_TOKEN")
      System.delete_env("MOSS_NODE")
      Application.delete_env(:moss, :service_req_options)
      Application.delete_env(:moss, :service_whole_bytes)
      Application.delete_env(:moss, :service_part_bytes)
    end)

    %{store: store}
  end

  test "a disk goes to the service by the node's own token, and comes back" do
    assert Service.available?()
    assert Service.get("computers/rock-7.sqlite") == :not_found
    assert :ok = Service.put("computers/rock-7.sqlite", "sqlite bytes")
    assert {:ok, "sqlite bytes"} = Service.get("computers/rock-7.sqlite")
    assert_received {:asked, "PUT", "/moss/disks/rock-7", ["Bearer node-token-test"]}
    assert :ok = Service.delete("computers/rock-7.sqlite")
    assert Service.get("computers/rock-7.sqlite") == :not_found
  end

  test "a large disk goes up in parts, in order" do
    Application.put_env(:moss, :service_whole_bytes, 10)
    Application.put_env(:moss, :service_part_bytes, 4)
    disk = "abcdefghijklmnopqr"
    assert :ok = Service.put("computers/rock-big.sqlite", disk)
    assert {:ok, ^disk} = Service.get("computers/rock-big.sqlite")
    assert_received {:asked, "POST", "/moss/disks/rock-big/uploads", _}
    assert_received {:asked, "PUT", "/moss/disks/rock-big/uploads/u1/5", _}
  end

  @seg "0/0000000000000001-0000000000000001.ltx"

  test "a computer's log from before packs is listed and read, segment by segment, never written",
       %{store: store} do
    Agent.update(store, &Map.put(&1, {:log, "rock-7", @seg}, "ltx"))
    assert {:ok, %{@seg => 3}} = Service.log_list("rock-7")
    assert {:ok, "ltx"} = Service.log_get("rock-7", @seg)
    assert_received {:asked, "GET", "/moss/logs/rock-7/" <> @seg, ["Bearer node-token-test"]}
    assert Service.log_get("rock-7", "0/0000000000000002-0000000000000002.ltx") == :not_found
    refute function_exported?(Service, :log_put, 3)
    refute function_exported?(Service, :log_delete, 2)
  end

  test "a segment's name is checked before anything is sent" do
    for bad <- ["../x", "0/x.ltx", "100/0000000000000001-0000000000000001.ltx", @seg <> ".tmp"],
        do: assert({:error, _} = Service.log_get("rock-7", bad))

    assert {:error, _} = Service.log_list("Rock.7")
    refute_received {:asked, _, _, _}
  end

  @pack "0000019a2b3c4d5e-0a1b2c3d.pack"

  test "a node's packs go to the service under its own name, and are read whole or by a range" do
    assert {:ok, %{}} = Service.pack_list()
    assert :ok = Service.pack_put(@pack, "header and bytes")
    assert_received {:asked, "PUT", "/moss/packs/node-test/" <> @pack, ["Bearer node-token-test"]}
    assert {:ok, %{@pack => 16}} = Service.pack_list()
    assert {:ok, "header and bytes"} = Service.pack_get(@pack, nil)
    assert {:ok, "and"} = Service.pack_get(@pack, {7, 9})
    assert {:ok, "bytes"} = Service.pack_get(@pack, {11, nil})
    assert :ok = Service.pack_delete(@pack)
    assert Service.pack_get(@pack, nil) == :not_found
    assert {:error, _} = Service.pack_put("../" <> @pack, "x")
  end

  test "the local store keeps packs the same way" do
    before = Application.get_env(:moss, :local_objects)

    Application.put_env(
      :moss,
      :local_objects,
      Path.join(System.tmp_dir!(), "moss-local-#{System.unique_integer([:positive])}")
    )

    assert {:ok, %{}} = Local.pack_list()
    assert :ok = Local.pack_put(@pack, "header and bytes")
    assert {:ok, %{@pack => 16}} = Local.pack_list()
    assert {:ok, "and"} = Local.pack_get(@pack, {7, 9})
    assert {:ok, "bytes"} = Local.pack_get(@pack, {11, nil})
    assert :ok = Local.pack_delete(@pack)
    assert Local.pack_get(@pack, nil) == :not_found
    Application.put_env(:moss, :local_objects, before)
  end

  test "only computers' disks go to the service, and nothing goes without a token" do
    assert {:error, _} = Service.put("probe/x.bin", "x")
    System.delete_env("MOSS_NODE_TOKEN")

    unless Moss.Keys.keychain("moss-node-token"),
      do: assert({:error, :no_token} = Service.get("computers/rock-7.sqlite"))
  end

  # A real round trip through arock.ai; needs this node's token. Run with `mix test --only service`.
  @tag :service
  test "the service round-trips a disk" do
    Application.delete_env(:moss, :service_req_options)
    System.delete_env("MOSS_NODE_TOKEN")
    key = "computers/probe-#{System.system_time(:millisecond)}.sqlite"
    body = :crypto.strong_rand_bytes(256 * 1024)
    assert Service.available?()
    assert :ok = Service.put(key, body)
    assert {:ok, ^body} = Service.get(key)
    assert :ok = Service.delete(key)
    assert Service.get(key) == :not_found
  end
end

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
    System.put_env("MOSS_NODE_TOKEN", "node-token-test")
    Application.put_env(:moss, :service_req_options, plug: Moss.FakeService.plug(self()))

    on_exit(fn ->
      System.delete_env("MOSS_NODE_TOKEN")
      Application.delete_env(:moss, :service_req_options)
      Application.delete_env(:moss, :service_whole_bytes)
      Application.delete_env(:moss, :service_part_bytes)
    end)
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

  test "a computer's log goes to the service segment by segment, under its own id" do
    assert {:ok, %{}} = Service.log_list("rock-7")
    assert :ok = Service.log_put("rock-7", @seg, "ltx")
    assert_received {:asked, "PUT", "/moss/logs/rock-7/" <> @seg, ["Bearer node-token-test"]}
    assert {:ok, %{@seg => 3}} = Service.log_list("rock-7")
    assert {:ok, "ltx"} = Service.log_get("rock-7", @seg)
    assert :ok = Service.log_delete("rock-7", @seg)
    assert Service.log_get("rock-7", @seg) == :not_found
  end

  test "a segment's name is checked before anything is sent" do
    for bad <- ["../x", "0/x.ltx", "100/0000000000000001-0000000000000001.ltx", @seg <> ".tmp"],
        do: assert({:error, _} = Service.log_put("rock-7", bad, "x"))

    assert {:error, _} = Service.log_list("Rock.7")
    refute_received {:asked, _, _, _}
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

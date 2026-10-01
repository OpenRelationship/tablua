defmodule Moss.ShipperTest do
  # Arock's PROJECT.md §15.4: the shipper sends the segments Litestream writes to the node's file replica through
  # the service with the node's own token, deletes the ones compacted away, and survives a restart. Litestream
  # itself is not needed here: the replica's files are written by hand (replication_test.exs runs the real one).
  use ExUnit.Case, async: false

  alias Moss.{Litestream, Objects}
  alias Moss.Objects.Shipper

  @a "0/0000000000000001-0000000000000001.ltx"
  @b "0/0000000000000002-0000000000000002.ltx"
  @c "1/0000000000000001-0000000000000002.ltx"

  setup do
    work = Path.join(System.tmp_dir!(), "moss-shipper-#{System.unique_integer([:positive])}")
    before = Map.new([:work_dir, :objects, :ship_ms], &{&1, Application.get_env(:moss, &1)})
    Application.put_env(:moss, :work_dir, work)
    Application.put_env(:moss, :objects, :service)
    # the rounds wait; each test ships when it says
    Application.put_env(:moss, :ship_ms, 3_600_000)
    System.put_env("MOSS_NODE_TOKEN", "node-token-test")
    Application.put_env(:moss, :service_req_options, plug: Moss.FakeService.plug(self(), [@c]))

    on_exit(fn ->
      for {k, v} <- before,
          do:
            if(v == nil,
              do: Application.delete_env(:moss, k),
              else: Application.put_env(:moss, k, v)
            )

      System.delete_env("MOSS_NODE_TOKEN")
      Application.delete_env(:moss, :service_req_options)
      File.rm_rf!(work)
    end)

    start_supervised!(Shipper)
    :ok
  end

  defp segment(id, name, body) do
    file = Path.join([Litestream.replica_dir(id), "ltx", name])
    File.mkdir_p!(Path.dirname(file))
    File.write!(file, body)
  end

  defp drop(id, name), do: File.rm!(Path.join([Litestream.replica_dir(id), "ltx", name]))

  defp puts do
    receive do
      {:asked, "PUT", _, _} -> 1 + puts()
      {:asked, _, _, _} -> puts()
    after
      0 -> 0
    end
  end

  test "new segments go up, compacted ones are deleted after, and the store holds what the replica holds" do
    segment("rock-1", @a, "one")
    assert {:ok, %{put: 1, deleted: 0}} = Shipper.ship("rock-1")
    segment("rock-1", @b, "two")
    drop("rock-1", @a)
    assert {:ok, %{put: 1, deleted: 1}} = Shipper.ship("rock-1")
    assert {:ok, %{@b => 3}} = Objects.log_list("rock-1")
    assert {:ok, "two"} = Objects.log_get("rock-1", @b)
    assert {:ok, %{put: 0, deleted: 0}} = Shipper.ship("rock-1")
  end

  test "a restarted shipper sends nothing twice: it starts from the store's own list" do
    segment("rock-2", @a, "one")
    segment("rock-2", @b, "two")
    assert {:ok, %{put: 2}} = Shipper.ship("rock-2")
    assert puts() == 2
    stop_supervised!(Shipper)
    start_supervised!(Shipper)
    assert {:ok, %{put: 0, deleted: 0}} = Shipper.ship("rock-2")
    assert puts() == 0
  end

  test "a put that fails deletes nothing, and the next round sends it" do
    segment("rock-3", @a, "one")
    assert {:ok, _} = Shipper.ship("rock-3")
    segment("rock-3", @c, "compacted")
    drop("rock-3", @a)
    assert {:error, why} = Shipper.ship("rock-3")
    assert why =~ "500"
    assert {:ok, %{@a => 3}} = Objects.log_list("rock-3")
  end

  test "a computer with no segment on the node deletes nothing from the store" do
    segment("rock-4", @a, "one")
    assert {:ok, _} = Shipper.ship("rock-4")
    File.rm_rf!(Litestream.replica_dir("rock-4"))
    assert {:ok, %{put: 0, deleted: 0}} = Shipper.ship("rock-4")
    assert {:ok, %{@a => 3}} = Objects.log_list("rock-4")
  end

  test "retire ships the last segments and only then cleans up; a failed ship leaves the files" do
    segment("rock-5", @a, "one")
    me = self()
    assert {:ok, %{put: 1}} = Shipper.retire("rock-5", fn -> send(me, :cleaned) end)
    assert_received :cleaned
    segment("rock-6", @c, "refused")
    assert {:error, _} = Shipper.retire("rock-6", fn -> send(me, :cleaned) end)
    assert {:error, _} = Shipper.retire("rock-never", fn -> send(me, :cleaned) end)
    refute_received :cleaned
  end

  test "a round ships every computer in the replica" do
    segment("rock-7", @a, "one")
    segment("rock-8", @b, "two")
    send(Process.whereis(Shipper), :round)
    :sys.get_state(Shipper)
    assert {:ok, %{@a => 3}} = Objects.log_list("rock-7")
    assert {:ok, %{@b => 3}} = Objects.log_list("rock-8")
  end

  test "a computer with no log in the store restores nothing" do
    assert Shipper.restore("rock-9", Path.join(System.tmp_dir!(), "never.sqlite")) == :none
  end
end

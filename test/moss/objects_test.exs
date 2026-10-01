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

  # Arock's /moss/disks, played in memory: whole disks and disks in parts, by the node's token.
  defp fake_service(test) do
    {:ok, store} = Agent.start_link(fn -> %{} end)

    fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn, length: 1_000_000_000)

      send(
        test,
        {:asked, conn.method, conn.request_path, Plug.Conn.get_req_header(conn, "authorization")}
      )

      ["moss", "disks", id | rest] = String.split(conn.request_path, "/", trim: true)

      case {conn.method, rest} do
        {"GET", []} ->
          case Agent.get(store, &Map.get(&1, id)) do
            nil -> Plug.Conn.send_resp(conn, 404, "{}")
            disk -> Plug.Conn.send_resp(conn, 200, disk)
          end

        {"PUT", []} ->
          Agent.update(store, &Map.put(&1, id, body))
          Plug.Conn.send_resp(conn, 204, "")

        {"DELETE", []} ->
          Agent.update(store, &Map.delete(&1, id))
          Plug.Conn.send_resp(conn, 204, "")

        {"POST", ["uploads"]} ->
          Plug.Conn.send_resp(conn, 200, ~s({"upload":"u1"}))

        {"PUT", ["uploads", "u1", n]} ->
          Agent.update(store, &Map.put(&1, {id, String.to_integer(n)}, body))
          Plug.Conn.send_resp(conn, 200, ~s({"etag":"e#{n}"}))

        {"POST", ["uploads", "u1", "complete"]} ->
          %{"parts" => parts} = Jason.decode!(body)

          whole =
            Enum.map_join(parts, fn %{"part" => n, "etag" => "e" <> m} ->
              ^m = to_string(n)
              Agent.get(store, &Map.fetch!(&1, {id, n}))
            end)

          Agent.update(store, &Map.put(&1, id, whole))
          Plug.Conn.send_resp(conn, 204, "")
      end
    end
  end

  setup do
    System.put_env("MOSS_NODE_TOKEN", "node-token-test")
    Application.put_env(:moss, :service_req_options, plug: fake_service(self()))

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

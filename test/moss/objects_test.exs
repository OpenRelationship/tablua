defmodule Moss.ObjectsTest do
  use ExUnit.Case, async: true

  alias Moss.Objects.{Local, R2}

  test "the local store puts, gets and deletes, and a missing key is not found" do
    key = "probe/#{System.unique_integer([:positive])}.bin"
    assert Local.get(key) == :not_found
    assert :ok = Local.put(key, <<0, 1, 2, 255>>)
    assert Local.get(key) == {:ok, <<0, 1, 2, 255>>}
    assert :ok = Local.delete(key)
    assert Local.get(key) == :not_found
    assert :ok = Local.delete(key)
  end

  test "an R2 request names the object under the account's bucket and carries the token as a bearer" do
    req = R2.build(:put, "runs/a b.sqlite", "sqlite bytes", "tok-123")

    req =
      Req.merge(req,
        plug: fn conn ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          send(self(), {:sent, conn.method, conn.host, conn.request_path, conn.req_headers, body})
          Plug.Conn.send_resp(conn, 200, "{}")
        end
      )

    assert {:ok, %{status: 200}} = Req.request(req)
    assert_received {:sent, "PUT", "api.cloudflare.com", path, headers, "sqlite bytes"}

    assert path ==
             "/client/v4/accounts/6d4b74aeb10f455fbf88141901e7595d/r2/buckets/volvox-runs/objects/runs/a%20b.sqlite"

    assert {"authorization", "Bearer tok-123"} in headers
    assert {"content-type", "application/octet-stream"} in headers
  end

  # A real round trip; needs `npx wrangler login`. Run with `mix test --only r2`.
  @tag :r2
  test "R2 round-trips an object under probe/" do
    key = "probe/moss-#{System.system_time(:millisecond)}.bin"
    body = :crypto.strong_rand_bytes(256 * 1024)
    assert R2.available?()
    assert :ok = R2.put(key, body)
    assert {:ok, ^body} = R2.get(key)
    assert :ok = R2.delete(key)
    assert R2.get(key) == :not_found
  end
end

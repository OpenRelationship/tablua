defmodule Moss.HardeningTest do
  # The holes from the 2026-10-01 security review (Arock PROJECT.md §14.7, goal 2) that do not depend on the
  # language: each test here failed before its fix.
  use ExUnit.Case, async: false

  alias Moss.Computer
  alias Moss.Computer.{Disk, Net}

  defp id, do: "hard-#{System.unique_integer([:positive])}"
  defp sh(id, line), do: Computer.run(id, line)

  defp stubbed(fun) do
    Req.Test.stub(Net, fun)
    c = id()
    Req.Test.allow(Net, self(), Computer.wake!(c))
    c
  end

  defp with_env(key, value, fun) do
    old = Application.get_env(:moss, key)
    Application.put_env(:moss, key, value)

    try do
      fun.()
    after
      if old == nil,
        do: Application.delete_env(:moss, key),
        else: Application.put_env(:moss, key, old)
    end
  end

  test "an unknown curl -X method is refused, and the computer goes on" do
    c = stubbed(fn conn -> Plug.Conn.send_resp(conn, 200, "ok") end)

    assert %{code: 2, err: "curl: no such method: BREW\n"} =
             sh(c, "curl -X BREW http://93.184.215.14/")

    assert %{code: 0, out: "ok"} = sh(c, "curl http://93.184.215.14/")
  end

  test "a computer's id is plain: lower-case letters, digits and dashes, at most 64" do
    for bad <- [
          "../escape",
          "a/b",
          "Rock",
          "",
          "-lead",
          String.duplicate("a", 65),
          "a b",
          "rock.7"
        ] do
      assert_raise ArgumentError, fn -> Computer.run(bad, "true") end
    end

    assert %{code: 0} = Computer.run("rock-7-#{System.unique_integer([:positive])}", "true")
  end

  test "curl and the browser stop at the size limit" do
    c = stubbed(fn conn -> Plug.Conn.send_resp(conn, 200, String.duplicate("x", 5000)) end)

    with_env(:net_max_bytes, 1000, fn ->
      assert %{code: 63, err: "curl: the answer is over 1000 bytes\n"} =
               sh(c, "curl http://93.184.215.14/big")

      assert %{code: 6, err: err} = sh(c, "open http://93.184.215.14/big")
      assert err =~ "over 1000 bytes"
    end)

    assert %{code: 0} = sh(c, "curl -o big.txt http://93.184.215.14/big")
  end

  test "a name is resolved once, and the request goes to the address that was checked" do
    test = self()

    {:ok, answers} = Agent.start_link(fn -> [[{93, 184, 215, 14}], [{127, 0, 0, 1}]] end)

    resolver = fn _host ->
      Agent.get_and_update(answers, fn
        [a | rest] -> {a, rest}
        [] -> {[{127, 0, 0, 1}], []}
      end)
    end

    c =
      stubbed(fn conn ->
        send(test, {:to, conn.host, Plug.Conn.get_req_header(conn, "host")})
        Plug.Conn.send_resp(conn, 200, "public")
      end)

    with_env(:resolver, resolver, fn ->
      assert %{code: 0, out: "public"} = sh(c, "curl http://rebind.example/")
    end)

    assert_received {:to, "93.184.215.14", ["rebind.example"]}
  end

  test "a computer's disk has a quota" do
    # the quota holds the log too: alog's tables (about 124 KB empty), and a file's recall text beside its bytes
    with_env(:disk_max_bytes, 512 * 1024, fn ->
      c = id()
      big = String.duplicate("x", 200 * 1024)
      assert %{code: 0} = sh(c, "lua -e 'fs.write(\"a.txt\", string.rep(\"x\", 200 * 1024))'")

      assert %{code: 1, err: err} =
               sh(c, "lua -e 'assert(fs.write(\"b.txt\", string.rep(\"x\", 200 * 1024)))'")

      assert err =~ "full"
      assert {:ok, ^big} = Disk.read(:sys.get_state(Computer.wake!(c)).disk, "/home/a.txt")
    end)
  end
end

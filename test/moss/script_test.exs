defmodule Moss.ScriptTest do
  # The computer's language is Lua on the BEAM (Moss.Computer.Script): the computer's own files, web, JSON and
  # mail are its library, and every run is bounded in instructions, memory, output and time.
  use ExUnit.Case, async: false

  alias Moss.Computer
  alias Moss.Computer.{Disk, Net}

  defp id, do: "script-#{System.unique_integer([:positive])}"
  defp sh(id, line), do: Computer.run(id, line)

  defp put(c, path, text),
    do: :ok = Disk.write(:sys.get_state(Computer.wake!(c)).disk, path, text)

  test "a script reads its args and stdin, writes the computer's files, and exits with its own status" do
    c = id()

    put(c, "/home/count.lua", ~S"""
    local n = 0
    for line in io.lines() do n = n + 1 end
    fs.write("notes/count.txt", arg[1] .. " " .. n)
    print(fs.read("notes/count.txt"), fs.exists("notes"), fs.isdir("notes"), #fs.list("notes"))
    os.exit(tonumber(arg[2]))
    """)

    assert %{code: 4, out: "lines 2\ttrue\ttrue\t1\n"} =
             sh(c, "echo 'a\nb' | lua count.lua lines 4")

    assert %{code: 0, out: "lines 2"} = sh(c, "cat notes/count.txt")
  end

  test "require loads modules from the working folder, then /home/lib" do
    c = id()
    put(c, "/home/lib/plants.lua", "return { water = function(p) return p .. ' watered' end }")
    put(c, "/home/app/util/text.lua", "return { shout = string.upper }")

    assert %{code: 0, out: "FERN watered\n"} =
             sh(
               c,
               ~s|cd app && lua -e 'print(require("plants").water(require("util.text").shout("fern")))'|
             )

    assert %{code: 1, err: "lua: " <> err} = sh(c, ~s|lua -e 'require("nope")'|)
    assert err =~ "module 'nope' not found"
  end

  test "errors name the script; pcall catches them; JSON goes both ways" do
    c = id()
    assert %{code: 1, err: "lua: (command line):1: boom\n"} = sh(c, ~s|lua -e 'error("boom")'|)

    assert %{code: 0, out: "caught\n"} =
             sh(c, ~s|lua -e 'print(select(2, pcall(error, "caught", 0)))'|)

    assert %{code: 0, out: ~s(true\t[1,2]\t{"a":"b"}\n)} =
             sh(
               c,
               ~s|lua -e 'local t = json.decode([[{"x":[1,{"y":true}]}]]) print(t.x[2].y, json.encode({1,2}), json.encode({a="b"}))'|
             )
  end

  test "there is nothing to reach but the computer: no shell, no node files, no environment" do
    c = id()

    assert %{code: 0, out: "nil\tnil\tfalse\tfalse\tfalse\n"} =
             sh(
               c,
               ~s|lua -e 'print(io.open, debug.getupvalue, pcall(os.execute, "ls"), pcall(os.getenv, "HOME"), (pcall(require, "os")))'|
             )
  end

  test "a run is bounded: instructions, memory, string size and output each end it" do
    c = id()

    assert %{code: 1, err: "lua: " <> e1} =
             sh(c, ~s|lua -e 'local t = {} for i = 1, 3e8 do t[i % 10] = i end'|)

    assert e1 =~ "instruction budget exceeded"

    assert %{code: 137, err: "lua: out of memory" <> _} =
             sh(
               c,
               ~s|lua -e 'local t = {} for i = 1, 1e8 do t[i] = string.rep("x", 100) .. i end'|
             )

    assert %{code: 0, out: "false\tresulting string too large\n"} =
             sh(c, ~s|lua -e 'print(pcall(string.rep, "x", 1e9))'|)

    assert %{code: 1, err: "lua: more than 1024 KB of output\n"} =
             sh(c, ~s|lua -e 'while true do print(string.rep("x", 1000)) end'|)

    # the computer is still there afterwards
    assert %{code: 0, out: "ok\n"} = sh(c, ~s|lua -e 'print("ok")'|)
  end

  test "http goes out under the computer's web rules" do
    test = self()

    Req.Test.stub(Net, fn conn ->
      case conn.request_path do
        "/echo" ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          send(test, {:fetched, conn.method, Plug.Conn.get_req_header(conn, "x-a"), body})

          conn
          |> Plug.Conn.put_resp_header("x-plant", "fern")
          |> Plug.Conn.send_resp(201, ~s({"n":2}))

        "/away" ->
          conn
          |> Plug.Conn.put_resp_header("location", "http://10.0.0.8/")
          |> Plug.Conn.send_resp(302, "")
      end
    end)

    c = id()
    Req.Test.allow(Net, self(), Computer.wake!(c))

    put(c, "/home/f.lua", ~S"""
    local r = http.post("http://93.184.215.14/echo", json.encode({ n = 1 }), { ["x-a"] = "1" })
    print(r.status, r.headers["x-plant"], json.decode(r.body).n)
    print(http.get("http://93.184.215.14/away"))
    print(http.get("http://127.0.0.1:4000/"))
    print(http.request({ method = "TRACE", url = "http://93.184.215.14/echo" }))
    """)

    assert %{code: 0, out: out} = sh(c, "lua f.lua")

    assert [
             "201\tfern\t2",
             "nil\t10.0.0.8 is not on the public internet",
             "nil\t127.0.0.1 is not on the public internet",
             "nil\tno such method: TRACE"
           ] = String.split(out, "\n", trim: true)

    assert_received {:fetched, "POST", ["1"], ~s({"n":1})}
  end
end

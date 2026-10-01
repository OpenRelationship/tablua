defmodule VolvoxServer.ComputerTest do
  # Volvox PROJECT.md §14: every agent its own computer inside the BEAM. Its disk is its SQLite file, its
  # shell runs commands and WASI programs against a kernel answered here, its browser keeps pages headless,
  # and nothing it does reaches the node or another agent's computer.
  use ExUnit.Case, async: false

  alias VolvoxServer.{Computer, Objects}
  alias VolvoxServer.Computer.{Net, Page}

  defp id, do: "computer-#{System.unique_integer([:positive])}"
  defp sh(id, line), do: Computer.run(id, line)

  # a computer whose web is this test's stub
  defp stubbed do
    c = id()
    Req.Test.allow(Net, self(), Computer.wake!(c))
    c
  end

  test "files, folders, pipes, redirects and variables, all on the computer's own disk" do
    c = id()
    assert %{code: 0, out: "/home\n"} = sh(c, "pwd")

    assert %{code: 0} =
             sh(
               c,
               "mkdir -p notes/old && echo 'buy moss' > notes/todo.txt && echo 'water fern' >> notes/todo.txt"
             )

    assert %{out: "1:buy moss\n"} = sh(c, "cat notes/todo.txt | grep -n moss")
    assert %{out: "water fern\n"} = sh(c, "sort -r notes/todo.txt | head -1")
    assert %{out: "hi pebbles $NAME\n"} = sh(c, "export NAME=pebbles; echo \"hi $NAME\" '$NAME'")
    assert %{out: "todo.txt\n", cwd: "/home/notes"} = sh(c, "cd notes && ls *.txt")
    assert %{code: 0} = sh(c, "mv todo.txt old/ && cp -r old copy")
    assert %{out: "./copy/todo.txt\n./old/todo.txt\n"} = sh(c, "find . -name '*.txt'")
    assert %{out: "127\n"} = sh(c, "nosuch; echo $?")
    assert %{code: 1, err: "rm: /home/notes/old: is a folder (rm -r)\n"} = sh(c, "rm old")
  end

  test "a WASI program runs on the kernel: JavaScript reads and writes the disk" do
    c = id()

    sh(
      c,
      ~s(echo 'name,cm' > plants.csv && echo 'fern,40' >> plants.csv && echo 'moss,2' >> plants.csv)
    )

    script =
      ~s|import * as std from "qjs:std"; const rows = std.loadFile("/home/plants.csv").trim().split("\\n").slice(1); | <>
        ~s|const f = std.open("/home/out.txt", "w"); f.puts(rows.length + " plants"); f.close(); console.log("read", rows.length);|

    sh(c, "echo '#{script}' > count.js")
    assert %{code: 0, out: "read 2\n"} = sh(c, "js count.js")
    assert %{out: "2 plants"} = sh(c, "cat out.txt")
    assert %{code: 3} = sh(c, "js -e 'import * as std from \"qjs:std\"; std.exit(3)'")
  end

  test "one computer never sees another's files" do
    {a, b} = {id(), id()}
    sh(a, "echo secret > mine.txt")
    assert %{code: 1} = sh(b, "cat mine.txt")
    assert %{code: 1} = sh(b, "cat /home/../../home/mine.txt")
    assert %{out: ""} = sh(b, "ls")
    assert %{out: "secret\n"} = sh(a, "cat mine.txt")
  end

  test "it sleeps to the object store and wakes with its files, folder and tabs" do
    c = id()
    sh(c, "mkdir work && cd work && echo kept > a.txt")
    ref = Process.monitor(Computer.whereis(c))
    assert :ok = Computer.sleep(c)
    assert_receive {:DOWN, ^ref, :process, _, :normal}, 2_000
    assert {:ok, _} = Objects.get(Objects.computer_key(c))
    {us, r} = :timer.tc(fn -> sh(c, "cat a.txt") end)
    assert %{out: "kept\n", cwd: "/home/work"} = r
    assert us < 500_000
  end

  test "the web is only the public internet, redirects included" do
    assert {:error, _} = Net.public("http://169.254.169.254/latest/meta-data")
    assert {:error, _} = Net.public("http://127.0.0.1:4000/")
    assert {:error, _} = Net.public("http://[::1]/")
    assert {:error, _} = Net.public("http://10.0.0.8/")
    assert {:error, _} = Net.public("file:///etc/passwd")
    assert {:ok, _} = Net.public("http://93.184.215.14/")

    Req.Test.stub(Net, fn conn ->
      conn
      |> Plug.Conn.put_resp_header("location", "http://169.254.169.254/")
      |> Plug.Conn.send_resp(302, "")
    end)

    assert %{code: 6, err: err} = sh(stubbed(), "curl -s http://93.184.215.14/")
    assert err =~ "not on the public internet"
  end

  @form """
  <html><head><title>Moss Shop</title><script>steal()</script></head><body>
  <h1>Join the newsletter</h1>
  <form method="post" action="/join">
    <label>Name <input name="name"></label>
    <label for="em">Email</label><input id="em" type="email" name="email">
    <label>Password <input type="password" name="pw"></label>
    <label><input type="radio" name="size" value="s"> Small</label>
    <label><input type="radio" name="size" value="l"> Large</label>
    <input type="hidden" name="token" value="t1">
    <button>Sign up</button>
  </form>
  <a href="/about">About us</a>
  </body></html>
  """

  test "a page reads as words and controls; a password is never typed; a form is sent as a browser sends it" do
    page = Page.new("http://93.184.215.14/", @form)
    assert page.title == "Moss Shop"
    assert page.text =~ "# Join the newsletter"
    refute page.text =~ "steal"

    assert ["Name", "Email", "Password", "Small", "Large", "Sign up", "About us"] ==
             for(c <- page.controls, c.role != "hidden", do: c.name)

    refute Page.html(page) =~ "<script"

    test = self()

    Req.Test.stub(Net, fn conn ->
      case conn.request_path do
        "/join" ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)
          send(test, {:sent, conn.method, URI.decode_query(body)})

          Plug.Conn.send_resp(
            conn,
            200,
            "<html><title>Welcome</title><body>Signed up</body></html>"
          )

        _ ->
          Plug.Conn.send_resp(conn, 200, @form)
      end
    end)

    c = stubbed()
    assert %{code: 0, out: out} = sh(c, "open http://93.184.215.14/")
    assert out =~ ~s([2] field "Email")

    assert %{code: 1, err: "type: a password is the person's own" <> _} =
             sh(c, "type Password hunter2")

    assert %{code: 0} =
             sh(c, "type Name Ada Lovelace && type Email ada@example.com && click Large")

    assert Page.html(Computer.Browser.front(Computer.view(c)).page) =~ ~s(value="ada@example.com")
    assert %{code: 0, out: out} = sh(c, "click 'Sign up'")
    assert out =~ "Signed up"

    assert_received {:sent, "POST",
                     %{
                       "name" => "Ada Lovelace",
                       "email" => "ada@example.com",
                       "pw" => "",
                       "size" => "l",
                       "token" => "t1"
                     }}

    assert %{code: 0, out: "Moss Shop" <> _} = sh(c, "back")
  end

  test "the core's exec port runs on the run's own computer, files first" do
    c = id()
    lua = VolvoxServer.Lua.Ports.bind(Lua.new(), computer: c)

    {[r], _lua} =
      Lua.eval!(lua, ~S"""
      return __host.exec{ cmd = "cat b.txt && echo made > a.txt && pwd", cwd = "/home/work", files = { ["b.txt"] = "given\n" } }
      """)

    assert %{"code" => 0, "stdout" => "given\n/home/work\n"} = Map.new(r)
    assert %{out: "made\n"} = sh(c, "cat /home/work/a.txt")
  end

  @hello ~S"""
  (module
    (import "wasi_snapshot_preview1" "fd_write" (func $write (param i32 i32 i32 i32) (result i32)))
    (import "wasi_snapshot_preview1" "args_sizes_get" (func $sizes (param i32 i32) (result i32)))
    (import "wasi_snapshot_preview1" "proc_exit" (func $exit (param i32)))
    (memory (export "memory") 1)
    (data (i32.const 16) "built here\n")
    (func (export "_start")
      (i32.store (i32.const 0) (i32.const 16))
      (i32.store (i32.const 4) (i32.const 11))
      (drop (call $write (i32.const 1) (i32.const 0) (i32.const 1) (i32.const 8)))
      (drop (call $sizes (i32.const 32) (i32.const 36)))
      (call $exit (i32.load (i32.const 32)))))
  """

  test "a module on the computer's own disk runs by its path, as the programs do" do
    c = id()
    bytes = Wasmex.Native.wat_to_wasm(@hello)
    pid = Computer.wake!(c)
    :sys.get_state(pid).disk |> VolvoxServer.Computer.Disk.write("/home/bin/hello.wasm", bytes)

    # it prints, and exits with its argument count
    assert %{code: 3, out: "built here\n"} = sh(c, "cd bin && ./hello.wasm one two")
    assert %{code: 1, out: "built here\n"} = sh(c, "/home/bin/hello.wasm")

    assert %{code: 126, err: "./notes.txt: not a WebAssembly program\n"} =
             sh(c, "echo hi > notes.txt && ./notes.txt")
  end

  test "C is compiled inside the computer and its program runs there, the shared /usr read-only" do
    c = id()

    src = ~S"""
    #include <stdio.h>
    int fib(int n) { return n < 2 ? n : fib(n - 1) + fib(n - 2); }
    int main(int argc, char **argv) {
      FILE *f = fopen("out.txt", "w"); fprintf(f, "fib(20)=%d\n", fib(20)); fclose(f);
      printf("hello %s\n", argc > 1 ? argv[1] : "nobody");
      return 7;
    }
    """

    :ok =
      VolvoxServer.Computer.Disk.write(
        :sys.get_state(Computer.wake!(c)).disk,
        "/home/src/hello.c",
        src
      )

    assert %{code: 0} = sh(c, "cd src && cc -o hello.wasm hello.c")
    assert %{code: 7, out: "hello pebbles\n"} = sh(c, "./hello.wasm pebbles")
    assert %{out: "fib(20)=6765\n"} = sh(c, "cat /home/src/out.txt")
    assert %{code: 1, err: "sh: /usr/include/x.h: eperm\n"} = sh(c, "echo no > /usr/include/x.h")
  end

  test "Python runs with its standard library from the shared /usr, on the computer's own files" do
    c = id()
    sh(c, "echo 'fern,40' > plants.csv && echo 'moss,2' >> plants.csv")

    py = ~S"""
    import csv, json, statistics
    rows = list(csv.reader(open("plants.csv")))
    json.dump({"mean": statistics.mean(int(r[1]) for r in rows)}, open("out.json", "w"))
    print(len(rows), "plants")
    """

    :ok =
      VolvoxServer.Computer.Disk.write(:sys.get_state(Computer.wake!(c)).disk, "/home/a.py", py)

    assert %{code: 0, out: "2 plants\n"} = sh(c, "python3 a.py")
    assert %{out: ~s({"mean": 21})} = sh(c, "cat out.json")
    assert %{code: 4} = sh(c, "python -c 'raise SystemExit(4)'")
  end

  test "Lua runs as its own program: errors unwind, files are the computer's, and there is no shell" do
    c = id()

    assert %{code: 0, out: "caught\n"} =
             sh(c, ~s|lua -e 'print(select(2, pcall(error, "caught", 0)))'|)

    assert %{code: 0, out: "moss\tnil\texit\t-1\n"} =
             sh(
               c,
               ~s|lua -e 'local f = io.open("t.txt", "w") f:write("moss") f:close() print(io.open("t.txt"):read("a"), os.execute("ls"))'|
             )

    assert %{code: 1, err: "lua: (command line):1: boom" <> _} = sh(c, ~s|lua -e 'error("boom")'|)
  end

  test "SQLite's own shell keeps a database on the computer's disk, with no way out to a shell" do
    c = id()

    assert %{code: 0} =
             sh(
               c,
               ~s|sqlite3 plants.db "create table p(n text, cm int); insert into p values('fern', 40), ('moss', 2);"|
             )

    assert %{out: "moss|2\nfern|40\n"} =
             sh(c, "sqlite3 plants.db 'select n, cm from p order by cm'")

    assert %{out: ~s([{"n":2}]\n)} =
             sh(c, "sqlite3 -json plants.db 'select count(*) as n from p'")

    assert %{out: "42\n"} = sh(c, "echo 'select sum(cm) from p;' | sqlite3 plants.db")
    assert %{code: 1, err: "Error: unknown command" <> _} = sh(c, "sqlite3 plants.db '.shell ls'")
  end

  test "fetch in JavaScript goes out through the host, under the computer's web rules" do
    test = self()

    Req.Test.stub(Net, fn conn ->
      case conn.request_path do
        "/echo" ->
          {:ok, body, conn} = Plug.Conn.read_body(conn)

          send(
            test,
            {:fetched, conn.method, Plug.Conn.get_req_header(conn, "content-type"), body}
          )

          conn
          |> Plug.Conn.put_resp_header("x-plant", "fern")
          |> Plug.Conn.put_resp_content_type("application/json")
          |> Plug.Conn.send_resp(201, ~s({"got": #{inspect(body)}}))

        "/away" ->
          conn
          |> Plug.Conn.put_resp_header("location", "http://10.0.0.8/")
          |> Plug.Conn.send_resp(302, "")

        "/bytes" ->
          Plug.Conn.send_resp(conn, 200, <<0, 1, 2, 255>>)
      end
    end)

    c = stubbed()

    js = ~S"""
    const r = await fetch("http://93.184.215.14/echo", { method: "post", body: JSON.stringify({ n: 1 }), headers: { "x-a": "1" } });
    const j = await r.json();
    console.log(r.status, r.ok, r.statusText, r.headers.get("x-plant"), j.got);
    const b = await (await fetch(new URL("http://93.184.215.14/bytes"))).bytes();
    console.log(b.length, b[3]);
    const f = await fetch("http://93.184.215.14/echo", { method: "PUT", body: new URLSearchParams("a=b c") });
    console.log(f.status);
    try { await fetch("http://93.184.215.14/away"); } catch (e) { console.log("refused:", e.message); }
    try { await fetch("http://127.0.0.1:4000/"); } catch (e) { console.log("refused:", e.message); }
    """

    :ok =
      VolvoxServer.Computer.Disk.write(
        :sys.get_state(c |> Computer.wake!()).disk,
        "/home/f.js",
        js
      )

    assert %{code: 0, out: out} = sh(c, "js --module f.js")

    assert [
             ~s(201 true Created fern {"n":1}),
             "4 255",
             "201",
             "refused: fetch failed: " <> away,
             "refused: fetch failed: " <> local
           ] = String.split(out, "\n", trim: true)

    assert away =~ "not on the public internet"
    assert local =~ "not on the public internet"
    assert_received {:fetched, "POST", ["text/plain;charset=UTF-8"], ~s({"n":1})}

    assert_received {:fetched, "PUT", ["application/x-www-form-urlencoded;charset=UTF-8"],
                     "a=b+c"}
  end

  test "Ruby runs with its library from the shared /usr, on the computer's own files" do
    c = id()

    assert %{code: 0, out: "4.0.0\n{\"a\":[1,2]}\nmoss\n"} =
             sh(
               c,
               ~S|ruby -e 'puts RUBY_VERSION; require "json"; puts JSON.generate({a: [1, 2]}); File.write("x.txt", "moss"); puts File.read("x.txt")'|
             )

    assert %{out: "moss"} = sh(c, "cat x.txt")
    assert %{code: 3} = sh(c, "ruby -e 'exit 3'")
  end

  test "Zig is compiled inside the computer and its program runs there, writing its output before it ends" do
    c = id()

    src = ~S"""
    const std = @import("std");
    pub fn main(init: std.process.Init) !void {
        var buf: [64]u8 = undefined;
        var w = std.Io.File.stdout().writer(init.io, &buf);
        try w.interface.print("hello from zig {d}\n", .{6 * 7});
        try w.interface.flush();
    }
    """

    :ok =
      VolvoxServer.Computer.Disk.write(
        :sys.get_state(Computer.wake!(c)).disk,
        "/home/main.zig",
        src
      )

    assert %{code: 0} = sh(c, "zig build-exe main.zig")
    assert %{code: 0, out: "hello from zig 42\n"} = sh(c, "./main.wasm")
  end

  test "a file renamed or removed while still open lands where a Unix program expects" do
    c = id()

    py = ~S"""
    import os
    f = open("save.tmp", "w"); f.write("saved"); f.flush()
    os.replace("save.tmp", "save.txt"); f.close()
    g = open("gone.txt", "w"); g.write("never"); os.remove("gone.txt"); g.close()
    print(open("save.txt").read(), os.path.exists("save.tmp"), os.path.exists("gone.txt"))
    """

    :ok =
      VolvoxServer.Computer.Disk.write(:sys.get_state(Computer.wake!(c)).disk, "/home/a.py", py)

    assert %{code: 0, out: "saved False False\n"} = sh(c, "python a.py")
  end

  @tag timeout: 120_000
  test "clang builds C and C++ inside the computer, step by step, leaving nothing in /tmp" do
    c = id()
    disk = :sys.get_state(Computer.wake!(c)).disk

    :ok =
      VolvoxServer.Computer.Disk.write(
        disk,
        "/home/hello.c",
        "#include <stdio.h>\n#include <math.h>\nint main(void) { printf(\"%.3f\\n\", sqrt(2.0)); return 4; }\n"
      )

    :ok =
      VolvoxServer.Computer.Disk.write(
        disk,
        "/home/hi.cc",
        "#include <iostream>\n#include <vector>\nint main() { std::vector<int> v{1, 2, 3}; int s = 0; for (int x : v) s += x; std::cout << s << std::endl; }\n"
      )

    assert %{code: 0} = sh(c, "clang -O2 hello.c -o hello.wasm -lm")
    assert %{code: 4, out: "1.414\n"} = sh(c, "./hello.wasm")
    assert %{code: 0} = sh(c, "clang++ -O2 hi.cc -o hi.wasm")
    assert %{code: 0, out: "6\n"} = sh(c, "./hi.wasm")
    assert %{out: ""} = sh(c, "ls /tmp")

    assert %{code: 1, err: err} =
             sh(c, "echo 'int main(void) { return x; }' > bad.c && clang bad.c")

    assert err =~ "use of undeclared identifier 'x'"
  end
end

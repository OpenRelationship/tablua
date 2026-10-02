defmodule Moss.ComputerTest do
  # Arock's PROJECT.md §14: every agent its own computer inside the BEAM. Its disk is its SQLite file, its
  # shell runs commands and Lua (script_test.exs) here, its browser keeps pages headless,
  # and nothing it does reaches the node or another agent's computer.
  use ExUnit.Case, async: false

  alias Moss.{Computer, Objects}
  alias Moss.Computer.{Net, Page}

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
               "mkdir -p files/notes/old && echo 'buy moss' > files/notes/todo.txt && echo 'water fern' >> files/notes/todo.txt"
             )

    assert %{out: "1:buy moss\n"} = sh(c, "cat files/notes/todo.txt | grep -n moss")
    assert %{out: "water fern\n"} = sh(c, "sort -r files/notes/todo.txt | head -1")
    assert %{out: "hi pebbles $NAME\n"} = sh(c, "export NAME=pebbles; echo \"hi $NAME\" '$NAME'")
    assert %{out: "todo.txt\n", cwd: "/home/files/notes"} = sh(c, "cd files/notes && ls *.txt")
    assert %{code: 0} = sh(c, "mv todo.txt old/ && cp -r old copy")
    assert %{out: "./copy/todo.txt\n./old/todo.txt\n"} = sh(c, "find . -name '*.txt'")
    assert %{out: "127\n"} = sh(c, "nosuch; echo $?")
    assert %{code: 1, err: "rm: /home/files/notes/old: is a folder (rm -r)\n"} = sh(c, "rm old")
  end

  test "an empty command between operators is nothing, or a mistake said plainly, never a crash" do
    c = id()
    assert %{code: 0, out: "a\nb\n"} = sh(c, "echo a; ; echo b")
    assert %{code: 0, out: "a\nb\n"} = sh(c, "echo a\n\necho b")

    assert %{code: 2, err: "sh: a command is missing beside && or ||\n"} =
             sh(c, "echo a && && echo b")

    assert %{code: 2, err: "sh: a command is missing beside && or ||\n"} =
             sh(c, "echo a || ; echo b")

    assert %{code: 2, err: "sh: a command is missing beside |\n"} = sh(c, "echo a | | cat")
    assert %{code: 0, out: "ok\n"} = sh(c, "echo ok")
  end

  test "one computer never sees another's files" do
    {a, b} = {id(), id()}
    sh(a, "echo secret > files/mine.txt")
    assert %{code: 1} = sh(b, "cat files/mine.txt")
    assert %{code: 1} = sh(b, "cat /home/../../home/files/mine.txt")
    # b holds only what every computer starts with: its procedures
    assert %{out: "org/\n"} = sh(b, "ls")
    assert %{out: "build.org\n"} = sh(b, "ls org/procedures")
    assert %{out: "secret\n"} = sh(a, "cat files/mine.txt")
  end

  test "it sleeps to the object store and wakes with its files, folder and tabs" do
    c = id()
    sh(c, "mkdir -p files/work && cd files/work && echo kept > a.txt")
    ref = Process.monitor(Computer.whereis(c))
    assert :ok = Computer.sleep(c)
    assert_receive {:DOWN, ^ref, :process, _, :normal}, 2_000
    assert {:ok, _} = Objects.get(Objects.computer_key(c))
    {us, r} = :timer.tc(fn -> sh(c, "cat a.txt") end)
    assert %{out: "kept\n", cwd: "/home/files/work"} = r
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
    assert Page.text(page) =~ "# Join the newsletter"
    refute Page.text(page) =~ "steal"

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
    lua = Moss.Lua.Ports.bind(Lua.new(), computer: c)

    {[r], _lua} =
      Lua.eval!(lua, ~S"""
      return __host.exec{ cmd = "cat b.txt && echo made > a.txt && pwd", cwd = "/home/files/work", files = { ["b.txt"] = "given\n" } }
      """)

    assert %{"code" => 0, "stdout" => "given\n/home/files/work\n"} = Map.new(r)
    assert %{out: "made\n"} = sh(c, "cat /home/files/work/a.txt")
  end
end

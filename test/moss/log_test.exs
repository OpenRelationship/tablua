defmodule Moss.LogTest do
  # Arock's PROJECT.md §14.7 goal 6 and §15: a computer's file writes, runs, app requests and mail are arock-log
  # events on its own SQLite file, its `nodes` the fold of that log, so what a computer did is its history.
  use ExUnit.Case, async: false

  alias Moss.{Computer, Db, Log}
  alias Moss.Computer.{App, Disk}

  defp id, do: "log-#{System.unique_integer([:positive])}"
  defp sh(c, line), do: Computer.run(c, line)
  defp disk(c), do: :sys.get_state(Computer.wake!(c)).disk

  # arock-log's own reading of the log, through its Lua: {keyword, actor, args} with content as its bytes
  defp events(c, keywords \\ nil) do
    d = disk(c)
    {:ok, [list]} = Log.alog(d, "events", [])

    for e <- plain(list), keywords == nil or e["keyword"] in keywords do
      spec = Map.get(Log.kinds(), e["keyword"], [])

      args =
        e["args"]
        |> Enum.with_index()
        |> Enum.map(fn {v, i} ->
          if String.ends_with?(Enum.at(spec, i, ""), "*"),
            do: elem(Log.alog(d, "blob", [v]), 1) |> hd(),
            else: v
        end)

      {e["keyword"], e["actor"], args}
    end
  end

  # a decoded Lua table: keys 1..n become a list, any other a map
  defp plain(pairs) when is_list(pairs) do
    keys = Enum.map(pairs, &elem(&1, 0))

    if pairs != [] and Enum.all?(keys, &is_integer/1),
      do: pairs |> Enum.sort() |> Enum.map(&plain(elem(&1, 1))),
      else: Map.new(pairs, fn {k, v} -> {k, plain(v)} end)
  end

  defp plain(v), do: v

  defp nodes(d) do
    {:ok, rows} = Db.exec(d.conn, "select path, dir, data, mtime from nodes order by path", [])
    rows
  end

  test "file writes, removes, moves and folders are events, by the agent" do
    c = id()
    sh(c, "true")

    assert %{code: 0} =
             sh(
               c,
               "mkdir -p files/notes/old && echo fern > files/notes/a.txt && mv files/notes/a.txt files/notes/b.txt && " <>
                 "rm files/notes/b.txt && rmdir files/notes/old"
             )

    assert [
             {"Make Folder", "agent", ["/home/files"]},
             {"Make Folder", "agent", ["/home/files/notes"]},
             {"Make Folder", "agent", ["/home/files/notes/old"]},
             {"Write File", "agent", ["/home/files/notes/a.txt", "fern\n"]},
             {"Move File", "agent", ["/home/files/notes/a.txt", "/home/files/notes/b.txt"]},
             {"Delete File", "agent", ["/home/files/notes/b.txt"]},
             {"Delete File", "agent", ["/home/files/notes/old"]}
           ] =
             events(c, ["Make Folder", "Write File", "Move File", "Delete File"])
             |> Enum.filter(&(elem(&1, 1) == "agent"))

    # a new disk: its root and its two folders, by the host
    assert [
             {"Make Folder", "host", ["/"]},
             {"Make Folder", "host", ["/home"]},
             {"Make Folder", "host", ["/tmp"]} | _
           ] = events(c)

    # the exec port's files go through the same writes
    Computer.exec(c, %{"files" => %{"files/x/y.txt" => "why"}, "cmd" => "true"})
    assert {"Write File", "agent", ["/home/files/x/y.txt", "why"]} in events(c)
  end

  test "rebuild folds the log back into the same nodes, from the start or a snapshot" do
    c = id()

    sh(
      c,
      "mkdir -p files/a/b && cd files && echo one > a/b/1.txt && echo two > a/2.txt && mv a z && rm z/2.txt"
    )

    sh(c, "echo three > z/b/1.txt && touch empty && mkdir keep")
    d = disk(c)
    before = nodes(d)
    {:ok, [dump]} = Log.alog(d, "dump", [])

    assert Enum.map(before, & &1["path"]) ==
             ~w(/ /home /home/files /home/files/empty /home/files/keep /home/files/z /home/files/z/b /home/files/z/b/1.txt
                /home/org /home/org/procedures /home/org/procedures/build.org /tmp)

    {:ok, _} = Log.alog(d, "rebuild", [])
    assert nodes(d) == before
    assert {:ok, [^dump]} = Log.alog(d, "dump", [])

    {:ok, _} = Log.alog(d, "snapshot", [])
    sh(c, "echo four > z/4.txt && rm -r z/b")
    after_snap = nodes(d)
    {:ok, _} = Log.alog(d, "rebuild", [])
    assert nodes(d) == after_snap
    assert {:ok, "four\n"} = Disk.read(d, "/home/files/z/4.txt")
  end

  test "a run is an event: its line, the folder it began in, its status, time, output and errors" do
    c = id()
    sh(c, "cd /tmp && echo hi && nosuch")

    assert [
             {"Run Command", "agent",
              ["cd /tmp && echo hi && nosuch", "/home", "127", ms, "hi\n", err]}
           ] =
             events(c, ["Run Command"])

    assert {_, ""} = Float.parse(ms)
    assert err =~ "nosuch"

    # a Lua run past its limits is logged with its limit's status
    sh(c, "lua -e 'while true do end'")

    assert [_, {"Run Command", "agent", ["lua -e 'while true do end'", "/tmp", status | _]}] =
             events(c, ["Run Command"])

    assert status != "0"
  end

  test "an app request is an event, by the person using the app" do
    c = id()

    :ok =
      Disk.write(disk(c), "/home/ui/add.lui", ~S"""
      <lua>
        function post.seen(req) fs.write("files/seen.txt", req.form.name or "") return { name = req.form.name } end
      </lua>
      <p>hi {{ result.name or "" }}</p>
      """)

    req = App.request("post", "/add", %{"q" => "1", "do" => "seen"}, %{"name" => "fern"}, [])
    assert {200, _, page, _} = Computer.serve(c, req)
    assert page =~ "<p>hi fern</p>"

    assert [{"Write File", "user", ["/home/files/seen.txt", "fern"]}] =
             events(c, ["Write File"])
             |> Enum.filter(&(elem(&1, 2) |> hd() == "/home/files/seen.txt"))

    assert [
             {"Serve Request", "user",
              ["POST", "/add", "200", ms, "do=seen&q=1&name=fern", ^page]}
           ] =
             events(c, ["Serve Request"])

    assert {_, ""} = Float.parse(ms)
  end

  test "recall finds a file by its text, and the event that wrote it" do
    c = id()
    sh(c, "mkdir -p files && echo 'the quokka sleeps under the fern' > files/notes.txt")
    {:ok, [found]} = Log.alog(disk(c), "recall", ["quokka"])
    found = plain(found)
    assert [%{"path" => "/home/files/notes.txt"}] = found["files"]
    assert Enum.any?(found["events"], &(&1["keyword"] == "Write File"))
  end

  test "an old disk with a nodes table moves onto the log once, as the host's events" do
    c = id()
    path = Path.join([Application.fetch_env!(:moss, :work_dir), "computers", c <> ".sqlite"])
    File.mkdir_p!(Path.dirname(path))
    {:ok, conn} = Db.open(path)

    {:ok, _} =
      Db.exec(
        conn,
        """
        create table nodes (path text primary key, dir integer not null, data blob, mtime integer not null);
        create table kept (key text primary key, value blob not null);
        insert into nodes values ('/', 1, null, 0);
        insert into nodes values ('/home', 1, null, 1700000000);
        insert into nodes values ('/home/old.txt', 0, x'6f6c640a', 1700000100);
        insert into nodes values ('/home/sub', 1, null, 1700000000);
        insert into nodes values ('/home/sub/b.bin', 0, x'00ff00', 1700000200);
        insert into nodes values ('/tmp', 1, null, 1700000000);
        """,
        []
      )

    :ok = Db.checkpoint_and_close(conn)

    assert %{out: "old\n"} = sh(c, "cat old.txt")
    d = disk(c)
    assert {:ok, %{mtime: 1_700_000_100, size: 4}} = Disk.stat(d, "/home/old.txt")
    assert {:ok, <<0, 255, 0>>} = Disk.read(d, "/home/sub/b.bin")

    assert [
             {"Make Folder", "host", ["/"]},
             {"Make Folder", "host", ["/home"]},
             {"Make Folder", "host", ["/home/sub"]},
             {"Make Folder", "host", ["/tmp"]},
             {"Write File", "host", ["/home/old.txt", "old\n"]},
             {"Write File", "host", ["/home/sub/b.bin", <<0, 255, 0>>]},
             {"Run Command", "agent", ["cat old.txt" | _]}
           ] = Enum.reject(events(c), &procedures?/1)

    assert {:ok, [%{"type" => "view"}]} =
             Db.exec(d.conn, "select type from sqlite_master where name = 'nodes'", [])

    # and only once
    :ok = Computer.sleep(c)
    sh(c, "true")
    assert length(Enum.reject(events(c, ["Write File"]), &procedures?/1)) == 2
  end

  # what the host writes on a first wake: the agent's procedures, an org file on the log (Moss.Computer.Procedures)
  defp procedures?({keyword, "host", [first | _]}),
    do:
      String.starts_with?(to_string(first), "/home/org") or
        keyword in ["Add Entry", "Set Header", "Set State", "Edit Entry"]

  defp procedures?(_), do: false
end

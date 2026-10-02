defmodule Moss.SessionBusyTest do
  # A computer's kept session (Session.keep/2, after every command) is written while another connection may hold the
  # file's write lock past SQLite's busy_timeout: Litestream checkpointing it, under a node's full load. The write
  # waits and tries again rather than crashing the computer, and a lock that never lets go is an error, not a crash.
  use ExUnit.Case, async: true

  alias Moss.Computer.{Disk, Session}
  alias Moss.Db

  setup do
    path = Path.join(System.tmp_dir!(), "moss-busy-#{System.unique_integer([:positive])}.sqlite")
    {:ok, disk} = Disk.open(path)
    # the lock outlasts SQLite's own wait at once, so the test is quick
    {:ok, _} = Db.exec(disk.conn, "pragma busy_timeout = 20", [])

    on_exit(fn -> for s <- ["", "-wal", "-shm"], do: File.rm(path <> s) end)
    %{disk: disk, path: path}
  end

  # another connection holds the write lock for `ms`, then lets it go
  defp hold(path, ms) do
    test = self()

    Task.async(fn ->
      {:ok, conn} = Db.open(path)
      {:ok, _} = Db.exec(conn, "begin immediate", [])
      send(test, :held)
      Process.sleep(ms)
      {:ok, _} = Db.exec(conn, "commit", [])
      Exqlite.Sqlite3.close(conn)
    end)
    |> tap(fn _ -> assert_receive :held, 5_000 end)
  end

  test "a session kept while the file is busy waits and is kept", %{disk: disk, path: path} do
    task = hold(path, 300)
    assert :ok = Session.keep(disk, %{cwd: "/home/busy"})
    Task.await(task)
    assert Session.kept(disk, nil) == %{cwd: "/home/busy"}
  end

  test "a file that stays busy is an error, never a crash", %{disk: disk, path: path} do
    task = hold(path, 2_000)
    assert {:error, why} = Session.keep(disk, %{cwd: "/home"}, tries: 2)
    assert why =~ "busy"
    Task.await(task)
  end
end

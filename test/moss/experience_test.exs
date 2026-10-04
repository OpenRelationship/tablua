defmodule Moss.ExperienceTest do
  # Experience shared between computers: what one computer's agent learned a step from, the next one reads too.
  use ExUnit.Case, async: false

  alias Moss.Computer.Experience

  setup do
    path = Path.join(System.tmp_dir!(), "experience-#{System.unique_integer([:positive])}.sqlite")
    System.put_env("MOSS_EXPERIENCE", path)

    on_exit(fn ->
      System.delete_env("MOSS_EXPERIENCE")
      File.rm(path)
    end)

    :ok
  end

  test "another computer's steps are read, its tasks its own; a computer's own are not read back" do
    :ok = Experience.add("a", "request-1", "Request", ["make plants"])
    :ok = Experience.add("a", "request-1", "Step", [1, "write_steps", "", 0, "", "", "building", "0.500"])
    :ok = Experience.add("a", "request-1", "Outcome", ["step", "complete", "", 1])
    # not what memory learns from: never shared
    :ok = Experience.add("a", "request-1", "Outcome", ["/home/features/plants.feature", "red", "{}", ""])
    :ok = Experience.add("a", "request-1", "Decide", ["x", "jev", "[]", "write_steps", "0.5"])

    rows = Experience.rows("b")
    assert Enum.map(rows, & &1["keyword"]) == ["Request", "Step", "Outcome"]
    assert Enum.all?(rows, &(&1["task"] == "a:request-1"))
    assert Enum.at(rows, 1)["args"] == ["1", "write_steps", "", "0", "", "", "building", "0.500"]
    assert Experience.rows("a") == []
  end

  test "with no shared file a computer learns from its own log alone" do
    System.delete_env("MOSS_EXPERIENCE")
    assert :ok = Experience.add("a", "request-1", "Step", [1, "run"])
    assert Experience.rows("b") == []
  end
  test "a finished run's Tablua rows go to the shared file, each task its computer's" do
    dir = Path.join(System.tmp_dir!(), "share-#{System.unique_integer([:positive])}.sqlite")
    on_exit(fn -> File.rm(dir) end)
    {:ok, conn} = Moss.Db.open(dir)

    {:ok, _} =
      Moss.Db.exec(conn, "create table if not exists tablua_run (task text primary key, shipped integer, steps integer)", [])

    {:ok, _} = Moss.Db.exec(conn, "insert into tablua_run (task, shipped, steps) values ('request-1', 1, 7)", [])
    assert :ok = Experience.share("a", conn)
    # again, as a second run would: replaced, not doubled
    assert :ok = Experience.share("a", conn)
    Exqlite.Sqlite3.close(conn)

    {:ok, shared} = Moss.Db.open(System.get_env("MOSS_EXPERIENCE"))
    assert {:ok, [%{"task" => "a|request-1", "shipped" => 1, "steps" => 7}]} =
             Moss.Db.exec(shared, "select * from tablua_run", [])

    Exqlite.Sqlite3.close(shared)
  end

  test "with no shared file, sharing does nothing" do
    System.delete_env("MOSS_EXPERIENCE")
    {:ok, conn} = Moss.Db.open(":memory:")
    assert :ok = Experience.share("a", conn)
  end
end

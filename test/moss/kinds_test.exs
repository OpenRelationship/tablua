defmodule Moss.KindsTest do
  # Arock's feature file-kinds: six kinds of file in six folders, at /home and in each app under apps/<name>/,
  # and a write anywhere else refused with the folder it belongs in. These are bdd/file-kinds.feature's
  # wrong-kind and wrong-folder scenarios, and the rest of the layout's rules.
  use ExUnit.Case, async: false

  alias Moss.Computer
  alias Moss.Computer.{Disk, Kinds}

  defp id, do: "kinds-#{System.unique_integer([:positive])}"
  defp sh(c, line), do: Computer.run(c, line)
  defp disk(c), do: :sys.get_state(Computer.wake!(c)).disk

  test "Scenario: a file outside the kinds is refused, naming the folders a file may go in" do
    c = id()
    assert {:error, why} = Disk.write(disk(c), "/home/run.sh", "echo hi")
    assert why =~ "features/, code/, ui/, data/, org/ or files/"
    assert why =~ "run.sh belongs in files/"
    assert {:error, :enoent} = Disk.read(disk(c), "/home/run.sh")
  end

  test "Scenario: a file in the wrong folder is refused, saying a page goes in ui/ as .org" do
    c = id()
    assert {:error, why} = Disk.write(disk(c), "/home/apps/plants/ui/index.lua", "return {}")
    assert why =~ "a page goes in ui/ as .org (org and Lua)"
    assert why =~ "index.lua is code and goes in code/"
  end

  test "each kind goes in its folder, at /home and in an app, and files/ takes any format" do
    c = id()

    for p <-
          ~w(/home/features/plants.feature /home/code/water.lua /home/code/steps/plants.lua
                /home/ui/index.lui /home/org/tasks.org /home/files/report.pdf /home/files/a/b/data.json
                /home/manifest.org /home/apps/plants/manifest.org /home/apps/plants/ui/list.lui
                /home/apps/plants/code/seed.lua /home/tmp-not-really/../files/x.csv /tmp/scratch.anything) do
      assert :ok = Disk.write(disk(c), p, "x"), p
    end
  end

  test "the shell and Lua hear the same refusal, and folders follow the same rules" do
    c = id()
    assert %{code: 1, err: err} = sh(c, "echo hi > notes.txt")
    assert err =~ "notes.txt belongs in files/"

    assert %{code: 1, err: "mkdir: /home/notes: folders under /home are" <> _} =
             sh(c, "mkdir notes")

    assert %{code: 0} = sh(c, "mkdir -p apps/plants/ui files/old")

    assert %{out: "nil\ta page goes in ui/ as .org (org and Lua); x.lua is code and goes in code/\n"} =
             sh(c, ~s|lua -e 'print(fs.write("ui/x.lua", "return 1"))'|)
  end

  test "a move or a copy lands only where every file under it may go" do
    c = id()
    assert %{code: 0} = sh(c, "mkdir -p files/pages && echo '<p>' > files/pages/a.html")
    assert %{code: 1, err: err} = sh(c, "mv files/pages ui")
    assert err =~ "ui/ holds pages; a.html goes in files/"
    assert %{code: 0} = sh(c, "mv files/pages files/old-pages")
  end

  test "data/ holds databases only, named .dbl" do
    c = id()

    assert {:error, "a database goes in data/" <> _} =
             Disk.write(disk(c), "/home/data/x.dbl", "bytes")

    assert %{out: "true\n"} = sh(c, ~s|lua -e 'print(db.open("data/plants.dbl") ~= nil)'|)

    assert %{out: "nil\ta database goes in data/ as .dbl" <> _} =
             sh(c, ~s|lua -e 'print(db.open("plants.db"))'|)
  end

  test "an app's name is a plain one, and apps/ holds only apps" do
    assert {:error, "an app's name is" <> _} = Kinds.file("/home/apps/Plants!/ui/index.lui")
    assert {:error, "apps/ holds apps" <> _} = Kinds.file("/home/apps/readme.md")
  end

  test "the host writes where it must" do
    c = id()
    host = %{disk(c) | actor: "host"}
    assert :ok = Disk.write(host, "/home/.kept-by-the-host", "x")
  end
end

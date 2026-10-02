defmodule Moss.HelpTest do
  # Arock's feature file-kinds, "Mercury's context": help per kind, each topic short and read from the files that
  # do the work, in place of the long help; the agent's procedures are org files on its computer's log, and with
  # help they are its model's context.
  use ExUnit.Case, async: false

  alias Moss.Computer

  defp id, do: "help-#{System.unique_integer([:positive])}"
  defp sh(c, line), do: Computer.run(c, line)

  test "help is an index of the kinds, and each topic is short" do
    c = id()
    %{code: 0, out: index} = sh(c, "help")

    for t <- ~w(feature code page data org files manifest loop mail open),
        do: assert(index =~ "help #{t}", t)

    assert byte_size(index) < 2_000

    for t <-
          ~w(feature code page kit classes data org files manifest loop mail open) ++
            ["org letter", "lua date"] do
      %{code: 0, out: out} = sh(c, "help #{t}")
      assert byte_size(out) in 300..5_000, "help #{t}: #{byte_size(out)} bytes"
    end

    assert sh(c, "help org letter").out =~ ":FROM:"
    assert sh(c, "help lua").out =~ "date"
  end

  test "the long help is gone" do
    c = id()

    for old <- ["help shroomi", "help app"] do
      # an old topic is no topic: it falls to the browser's help, which names none of the long references
      refute sh(c, old).out =~ "shroomi.components"
    end
  end

  test "the agent's procedures are org files on its log, and its model's context" do
    c = id()
    %{code: 0, out: text} = sh(c, "cat org/procedures/build.org")
    assert text =~ "#+TITLE: How I build"
    assert text =~ ":ID: e1"

    d = :sys.get_state(Computer.wake!(c)).disk
    adds = for {_, "Add Entry", [path | _]} <- Moss.Log.events(d.conn, ["Add Entry"]), do: path
    assert Enum.all?(adds, &(&1 == "/home/org/procedures/build.org")) and length(adds) == 3

    # an edit that rewrites history is refused, as any org is
    forged = String.replace(text, ":ID: e1", ":ID: e9")

    assert %{"code" => 2, "stderr" => why} =
             Computer.exec(c, %{
               "files" => %{"org/procedures/build.org" => forged},
               "cmd" => "true"
             })

    assert why =~ "org/procedures/build.org is refused"

    context = Moss.AgentLoop.context(c)
    assert context =~ "help page" and context =~ "How I work on a task"
  end
end

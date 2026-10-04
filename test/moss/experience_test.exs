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
end

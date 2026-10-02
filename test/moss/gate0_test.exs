defmodule Moss.Gate0Test do
  @moduledoc """
  Gate 0: every Arock Core unit test file runs unchanged in tv-labs lua on this
  host, each from a fresh copy of the base state, and every case passes
  (alog's, Shroomi's and rockmail's too).
  """
  use ExUnit.Case, async: true

  alias Moss.{Lua, LuaHost}

  @core Application.compile_env!(:moss, :core)
  @files for(
           dir <- ["library", "submodules/alog", "submodules/shroomi", "submodules/rockmail"],
           do: Path.wildcard(Path.join([@core, dir, "**/*_test.lua"]))
         )
         |> List.flatten()
         |> Enum.sort()

  test "the library has unit test files" do
    assert length(@files) >= 7
  end

  for file <- @files do
    rel = Path.relative_to(file, @core)

    @tag lua_test: rel
    test rel do
      {:ok, [cases]} = LuaHost.call(:unit, [unquote(rel), File.read!(unquote(file))])
      cases = Enum.map(Lua.list(cases), &Map.new/1)
      failed = for c <- cases, !c["ok"], do: "#{c["name"]}: #{c["err"]}"

      # a file of plain asserts (no mono.spec) passes by running to its end, which the call above did
      assert cases != [] or not (File.read!(unquote(file)) =~ "mono.spec")

      assert failed == [],
             "#{length(failed)} of #{length(cases)} failed:\n" <> Enum.join(failed, "\n")
    end
  end
end

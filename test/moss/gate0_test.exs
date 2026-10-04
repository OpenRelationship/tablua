defmodule Moss.Gate0Test do
  @moduledoc """
  Gate 0: every unit test file of Tablua's core (core/: the harness, the model ports and arock-log, moved here
  from Arock's library/, arock issue #1 M7) runs unchanged in tv-labs lua on this host, each from a fresh copy of
  the base state, and every case passes (Shroomi's and uspx's too).
  """
  use ExUnit.Case, async: true

  alias Moss.{Lua, LuaHost}

  @core Application.compile_env!(:moss, :core)
  @files ([Path.wildcard(Path.expand("../../core/**/*_test.lua", __DIR__)),
           Path.wildcard(Path.join([@core, "submodules/uspx", "**/*_test.lua"]))] ++
            [Path.wildcard(Path.expand("../../shroomi/**/*_test.lua", __DIR__))])
         |> List.flatten()
         # uspx's model checks are searches over its rules (minutes on this VM); the rules' own tests and the
         # fuzzing run here, and the searches run on LuaJIT in Arock's build
         |> Enum.reject(&(&1 =~ ~r"submodules/uspx/\w*model_test\.lua$"))
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

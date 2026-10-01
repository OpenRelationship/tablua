defmodule Moss.Gate0Test do
  @moduledoc """
  Gate 0: every Arock Core unit test file runs unchanged in tv-labs lua on this
  host, each from a fresh copy of the base state, and every case passes.
  """
  use ExUnit.Case, async: true

  alias Moss.{Lua, LuaHost}

  @library Path.join(Application.compile_env!(:moss, :core), "library")
  @files @library |> Path.join("**/*_test.lua") |> Path.wildcard() |> Enum.sort()

  test "the library has unit test files" do
    assert length(@files) >= 7
  end

  for file <- @files do
    rel = Path.relative_to(file, @library)

    @tag lua_test: rel
    test "library/#{rel}" do
      {:ok, [cases]} = LuaHost.call(:unit, [unquote(rel), File.read!(unquote(file))])
      cases = Enum.map(Lua.list(cases), &Map.new/1)
      failed = for c <- cases, !c["ok"], do: "#{c["name"]}: #{c["err"]}"
      assert cases != []

      assert failed == [],
             "#{length(failed)} of #{length(cases)} failed:\n" <> Enum.join(failed, "\n")
    end
  end
end

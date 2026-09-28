defmodule VolvoxServer.ColmTest do
  @moduledoc """
  The outline module under Wasmex against Volvox's LuaJIT path (wasmtime
  through suite.runner): stdout, stderr and status byte-identical for every
  file in the python-edit test data. The expected side is
  test/fixtures/outline, written by test/fixtures/outline/generate.lua.
  Then Volvox's own suite.python, in tv-labs lua over the colm port, makes
  the python-edit feature's edits.
  """
  use ExUnit.Case, async: true

  alias VolvoxServer.{Colm, LuaHost}

  @volvox Application.compile_env!(:volvox_server, :volvox)
  @data Path.join(@volvox, "context/projects/volvox/features/python-edit/test/data")
  @fixtures Path.expand("../fixtures/outline", __DIR__)

  defp data(name), do: File.read!(Path.join(@data, name))

  test "outline output is byte-identical to the LuaJIT path for every python-edit file" do
    names = @data |> File.ls!() |> Enum.sort()
    assert length(names) == 7

    for name <- names do
      {out, status, err} = Colm.run("outline", data(name))
      fixture = &File.read!(Path.join(@fixtures, name <> &1))
      assert out == fixture.(".out"), "#{name}: stdout differs"
      assert err == fixture.(".err"), "#{name}: stderr differs"
      assert "#{status}\n" == fixture.(".status"), "#{name}: status differs"
    end
  end

  test "an instance is recycled after 200 runs and keeps answering" do
    src = data("calc.py")
    want = Colm.run("outline", src)
    [{server, _}] = Registry.lookup(VolvoxServer.Colm.Registry, "outline")
    first = :sys.get_state(server).instance.pid
    for _ <- 1..210, do: assert(Colm.run("outline", src) == want)
    assert :sys.get_state(server).instance.pid != first
  end

  test "suite.python in tv-labs lua replaces and inserts through the colm port" do
    assert {:ok, [new]} =
             LuaHost.call(:python, ["replace", data("calc.py"), "Calc.div", data("div-new.py")])

    assert new == data("calc-replaced.py") or new <> "\n" == data("calc-replaced.py")

    assert {:ok, [new]} =
             LuaHost.call(:python, ["insert_after", data("calc.py"), "Calc.div", data("add.py")])

    assert new == data("calc-inserted.py") or new <> "\n" == data("calc-inserted.py")

    assert {:ok, [nil, why]} =
             LuaHost.call(:python, ["replace", data("calc.py"), "Calc.div", data("div-broken.py")])

    assert why =~ "the new text does not parse"

    assert {:ok, [text]} = LuaHost.call(:python, ["text", data("calc.py"), "Calc.mul", nil])
    assert text == data("mul-unit.py")
  end
end

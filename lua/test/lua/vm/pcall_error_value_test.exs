defmodule Lua.VM.PcallErrorValueTest do
  @moduledoc """
  Pins Lua 5.3 §6.1 `error` / `pcall` / `xpcall` error-value semantics:
  `error(value)` raises an arbitrary Lua value and `pcall` returns that
  value AS-IS as its second result — never a stringification. For string
  messages (and `level ~= 0`), `error` prepends a `source:line:` position
  prefix; `level == 0` suppresses it. Non-string values are never
  prefixed.

  Reference behavior (PUC Lua 5.3):

      $ lua -e 'local ok, err = pcall(function() error({code = 1}) end); print(ok, type(err), err.code)'
      false   table   1
      $ lua -e 'local ok, err = pcall(function() error(42) end); print(ok, type(err), err)'
      false   number  42
      $ lua -e 'local ok, err = pcall(function() error("boom") end); print(ok, type(err), err)'
      false   string  (command line):1: boom

  Each case runs under both execution engines: the default compile path
  (closures carry bytecode and run on the dispatcher) and with bytecode
  recursively stripped (closures run on the instruction interpreter).
  Both engines emit the `source:line:` prefix: the per-call line is baked
  into the call opcode at encode time, so the dispatcher publishes it via
  `current_position/0` at native-call boundaries exactly as the
  interpreter threads it. The prefix is pinned to the exact source line
  under both engines.
  """
  use ExUnit.Case, async: true

  alias Lua.Compiler
  alias Lua.Compiler.Prototype
  alias Lua.Parser
  alias Lua.VM
  alias Lua.VM.State
  alias Lua.VM.Stdlib

  defp run(code, engine) do
    {:ok, ast} = Parser.parse(code)
    {:ok, proto} = Compiler.compile(ast, source: "test.lua")

    proto =
      case engine do
        :compiled -> proto
        :interpreted -> strip_bytecode(proto)
      end

    state = Stdlib.install(State.new())
    {:ok, results, state} = VM.execute(proto, state)
    {results, state}
  end

  # `body` run inside `pcall(function() ... end)`, its first line being line
  # 2 of test.lua; returns the error value.
  defp pcall_error(body, engine) do
    {[false, err], _state} =
      run("local ok, err = pcall(function()\n" <> body <> "\nend)\nreturn ok, err", engine)

    err
  end

  # Forces every closure onto the instruction interpreter — the closure
  # tag flips on `proto.bytecode`, so stripping it recursively keeps the
  # whole program off the dispatcher.
  defp strip_bytecode(%Prototype{} = proto) do
    %{proto | bytecode: nil, prototypes: Enum.map(proto.prototypes, &strip_bytecode/1)}
  end

  for engine <- [:compiled, :interpreted] do
    @engine engine

    describe "pcall returns the raw error value (#{engine} engine)" do
      test "error with a table object passes the table through" do
        {results, _state} =
          run(
            """
            local ok, err = pcall(function()
              error({code = 1})
            end)
            return ok, type(err), err and err.code
            """,
            @engine
          )

        assert results == [false, "table", 1]
      end

      test "error with a number passes the number through" do
        {results, _state} =
          run(
            """
            local ok, err = pcall(function()
              error(42)
            end)
            return ok, type(err), err
            """,
            @engine
          )

        assert results == [false, "number", 42]
      end

      test "error with true passes the boolean through" do
        {results, _state} =
          run(
            """
            local ok, err = pcall(function()
              error(true)
            end)
            return ok, type(err), err
            """,
            @engine
          )

        assert results == [false, "boolean", true]
      end

      test "error with false passes false through (falsy-but-present value)" do
        {results, _state} =
          run(
            """
            local ok, err = pcall(function()
              error(false)
            end)
            return ok, type(err), err
            """,
            @engine
          )

        assert results == [false, "boolean", false]
      end

      test "error with no argument returns nil" do
        {results, _state} =
          run(
            """
            local ok, err = pcall(function()
              error()
            end)
            return ok, err == nil
            """,
            @engine
          )

        assert results == [false, true]
      end

      test "error with explicit nil returns nil" do
        {results, _state} =
          run(
            """
            local ok, err = pcall(function()
              error(nil)
            end)
            return ok, err == nil
            """,
            @engine
          )

        assert results == [false, true]
      end

      test "stdlib bad-argument error returns the raw string with its call site" do
        {results, _state} =
          run(
            """
            local ok, err = pcall(function()
              pairs("asdf")
            end)
            return ok, type(err), err
            """,
            @engine
          )

        assert [false, "string", err] = results
        assert err == "test.lua:2: bad argument #1 to 'pairs' (table expected, got string)"
      end
    end

    describe "error() position prefix on string messages (#{engine} engine)" do
      test "string error carries the §6.1 source:line: prefix" do
        {results, _state} =
          run(
            """
            local ok, err = pcall(function()
              error("boom")
            end)
            return ok, type(err), err
            """,
            @engine
          )

        assert [false, "string", err] = results

        # `error("boom")` sits on line 2 of the chunk. Pin the exact line
        # (not a loose `:\d+:`) so an off-by-one or a swapped
        # `{line, source}` destructure (`2:test.lua: boom`) fails here.
        # Both engines plumb the per-call line to native raise sites.
        assert err == "test.lua:2: boom"
      end

      test "level 0 suppresses the prefix" do
        {results, _state} =
          run(
            """
            local ok, err = pcall(function()
              error("hi", 0)
            end)
            return ok, err
            """,
            @engine
          )

        assert results == [false, "hi"]
      end

      test "level 2 blames the caller's line" do
        {results, _state} =
          run(
            """
            local function check(x)
              if not x then error("bad input", 2) end
            end
            local ok, err = pcall(function()
              check(false)
            end)
            return err
            """,
            @engine
          )

        assert results == ["test.lua:5: bad input"]
      end

      test "level 3 blames the caller's caller" do
        {results, _state} =
          run(
            """
            local function check(x)
              if not x then error("deep", 3) end
            end
            local function validate(x)
              check(x)
            end
            local ok, err = pcall(function()
              validate(false)
            end)
            return err
            """,
            @engine
          )

        assert results == ["test.lua:8: deep"]
      end
    end

    describe "xpcall hands the raw value to the handler (#{engine} engine)" do
      test "handler receives the untouched table" do
        {results, _state} =
          run(
            """
            local ok, err = xpcall(function()
              error({code = 2})
            end, function(e)
              return e
            end)
            return ok, type(err), err and err.code
            """,
            @engine
          )

        assert results == [false, "table", 2]
      end

      test "an erroring handler falls back to the original raw value" do
        {results, _state} =
          run(
            """
            local ok, err = xpcall(function()
              error({code = 2})
            end, function(_)
              error("handler boom")
            end)
            return ok, type(err), err and err.code
            """,
            @engine
          )

        assert results == [false, "table", 2]
      end
    end

    describe "internal errors keep their string messages (#{engine} engine)" do
      test "a call-nil TypeError stays a string and is not prefixed by error()" do
        {results, _state} =
          run(
            """
            local ok, err = pcall(function()
              local f = nil
              f()
            end)
            return ok, type(err), err
            """,
            @engine
          )

        assert [false, "string", err] = results
        assert err =~ "attempt to call a nil value"
      end

      test "an arithmetic TypeError stays a string" do
        {results, _state} =
          run(
            """
            local ok, err = pcall(function()
              return nil + 1
            end)
            return ok, type(err), err
            """,
            @engine
          )

        assert [false, "string", err] = results
        assert err =~ "attempt to perform arithmetic"
      end

      test "a stdlib bad-argument error stays a string" do
        {results, _state} =
          run(
            """
            local ok, err = pcall(function()
              return string.rep()
            end)
            return ok, type(err), err
            """,
            @engine
          )

        assert [false, "string", _err] = results
      end
    end

    # PUC-Lua prefixes every runtime error the VM raises with the
    # `chunkname:line:` of the faulting statement, and names the value that
    # failed.
    describe "VM errors carry the faulting position and a name (#{engine} engine)" do
      test "indexing a nil local" do
        assert pcall_error("local t = nil\nlocal y = 1\nreturn t.x", @engine) ==
                 "test.lua:4: attempt to index a nil value (local 't')"
      end

      test "declaring a function in an unset global table" do
        assert pcall_error("local a = 1\nfunction M.add_habit() end", @engine) ==
                 "test.lua:3: attempt to index a nil value (global 'M')"

        assert pcall_error("function M.sub.f() end", @engine) ==
                 "test.lua:2: attempt to index a nil value (global 'M')"

        assert pcall_error("M = {}\nfunction M.sub.f() end", @engine) ==
                 "test.lua:3: attempt to index a nil value (field 'sub' on global 'M')"

        assert pcall_error("local M\nfunction M:go() end", @engine) ==
                 "test.lua:3: attempt to index a nil value (local 'M')"
      end

      test "reading or assigning a field of an unset global" do
        assert pcall_error("M.x = 1", @engine) == "test.lua:2: attempt to index a nil value (global 'M')"
        assert pcall_error("return M.y", @engine) == "test.lua:2: attempt to index a nil value (global 'M')"
      end

      test "indexing a nil upvalue names its line" do
        assert pcall_error("local u\nlocal function f()\n  return u.x\nend\nreturn f()", @engine) ==
                 "test.lua:4: attempt to index a nil value (upvalue 'u')"
      end

      test "an error in a called function names the callee's line" do
        assert pcall_error("local function g(t)\n  return t.x\nend\nlocal z = 1\nreturn g(nil)", @engine) ==
                 "test.lua:3: attempt to index a nil value (local 't')"
      end

      test "concatenation names the operand that is not a string" do
        assert pcall_error("local q = {}\nreturn 'a' .. q", @engine) ==
                 "test.lua:3: attempt to concatenate a table value (local 'q')"

        assert pcall_error("local q = {}\nreturn q.name .. 'a'", @engine) ==
                 "test.lua:3: attempt to concatenate a nil value (field 'name' on local 'q')"
      end

      test "the length of a nil value is an error, not 0" do
        assert pcall_error("local t = {}\nreturn #t.items", @engine) ==
                 "test.lua:3: attempt to get length of a nil value (field 'items' on local 't')"
      end

      test "arithmetic, ordering and integer division by zero" do
        assert pcall_error("local n\nreturn n + 1", @engine) ==
                 "test.lua:3: attempt to perform arithmetic on a nil value (local 'n')"

        assert pcall_error("local q = {}\nreturn q < 1", @engine) ==
                 "test.lua:3: attempt to compare table with number"

        assert pcall_error("local z = 0\nreturn 1 % z", @engine) == "test.lua:3: attempt to perform 'n%0'"
      end

      test "a numeric for with a non-number limit" do
        assert pcall_error("local x = 1\nfor i = 1, nil do end", @engine) ==
                 "test.lua:3: 'for' limit must be a number"
      end

      test "assert's string message is prefixed, any other value passes through" do
        assert pcall_error("local x = 1\nassert(false, 'nope')", @engine) == "test.lua:3: nope"
        assert pcall_error("assert(nil)", @engine) == "test.lua:2: assertion failed!"

        {[false, "table"], _} =
          run("local ok, err = pcall(function() assert(false, {}) end)\nreturn ok, type(err)", @engine)
      end

      test "xpcall's handler sees the position and debug.traceback the frames" do
        {[false, tb], _state} =
          run(
            """
            local function inner(t) return t.x end
            local function outer() return inner(nil) end
            return xpcall(outer, debug.traceback)
            """,
            @engine
          )

        assert tb ==
                 "test.lua:1: attempt to index a nil value (local 't')\nstack traceback:\n\ttest.lua:2: in ?"
      end
    end
  end

  describe "compiled and interpreted engines agree on the error() prefix" do
    test "an in-VM pcall over error() yields byte-identical strings on both engines" do
      code = """
      local ok, err = pcall(function()
        error("boom")
      end)
      return ok, type(err), err
      """

      {[false, "string", compiled], _} = run(code, :compiled)
      {[false, "string", interpreted], _} = run(code, :interpreted)

      assert compiled == "test.lua:2: boom"
      assert compiled == interpreted
    end

    test "a native iterator raising mid-step yields byte-identical strings on both engines" do
      code = """
      local ok, err = pcall(function()
        for x in error, "deep", nil do end
      end)
      return ok, type(err), err
      """

      {[false, "string", compiled], _} = run(code, :compiled)
      {[false, "string", interpreted], _} = run(code, :interpreted)

      assert compiled == "test.lua:2: deep"
      assert compiled == interpreted
    end

    test "a native call raising inside a while condition keeps the condition's line" do
      code = """
      local ok, err = pcall(function()
        while error("wc") do end
      end)
      return ok, type(err), err
      """

      {[false, "string", compiled], _} = run(code, :compiled)
      {[false, "string", interpreted], _} = run(code, :interpreted)

      assert compiled == "test.lua:2: wc"
      assert compiled == interpreted
    end

    test "a native call raising inside a repeat-until condition keeps the loop's line" do
      code = """
      local ok, err = pcall(function()
        repeat
        until error("rc")
      end)
      return ok, type(err), err
      """

      {[false, "string", compiled], _} = run(code, :compiled)
      {[false, "string", interpreted], _} = run(code, :interpreted)

      # The condition body carries no `:source_line` of its own, so it
      # inherits the enclosing loop's line (the `repeat` at line 2) under
      # both engines — the point is that they agree, with no `:0:` leak.
      assert compiled == "test.lua:2: rc"
      assert compiled == interpreted
    end

    test "a stdlib ArgumentError yields byte-identical strings on both engines" do
      # An in-VM `pcall` over a bad-argument stdlib call returns the raw Lua
      # error value with the `source:line:` prefix of the call, as PUC-Lua's
      # `luaL_argerror` does. The point pinned here is that the dispatcher
      # and the interpreter agree byte-for-byte on that value, so the
      # per-call line plumbing cannot make the two engines diverge on the
      # bad-argument render.
      code = """
      local ok, err = pcall(function()
        pairs("asdf")
      end)
      return ok, type(err), err
      """

      {[false, "string", compiled], _} = run(code, :compiled)
      {[false, "string", interpreted], _} = run(code, :interpreted)

      assert compiled == "test.lua:2: bad argument #1 to 'pairs' (table expected, got string)"
      assert compiled == interpreted
    end
  end
end

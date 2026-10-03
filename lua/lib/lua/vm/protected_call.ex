defmodule Lua.VM.ProtectedCall do
  @moduledoc false

  # The Lua-facing error value handed back at a protected-call boundary
  # (`pcall`/`xpcall`, and `Lua.call_function/3`), per §6.1: the raised value
  # passes through verbatim, and a string message the VM raised itself gains
  # the `source:line: ` prefix PUC-Lua's `luaG_runerror` / `luaL_error` give
  # it, so the error names where it happened.
  #
  # Clause ordering is load-bearing:
  # 1. `error()`'s §6.1-prefixed string view (`RuntimeError.lua_value`);
  #    `error()` already applied its level, so it is never prefixed again.
  # 2. Type errors (indexing, calling, arithmetic, ...) and `assert`'s string
  #    message get the prefix of their raise site.
  # 3. Raw passthrough on KEY PRESENCE — `value: nil` (from `error()`) and
  #    `value: false` must match here so the boundary returns nil/false like
  #    PUC-Lua, never an `is_nil`-guarded fallthrough to the next clause.
  #    Other `RuntimeError`s (host `{:error, reason}`, stdlib failures) keep
  #    their value as raised.
  # 4. `ArgumentError` builds its message from individual fields and has no
  #    `:value` slot, so it gets its own clause that returns the prefixed raw
  #    `"bad argument #N to 'F' ..."` string — never the terminal-rendered
  #    `Exception.message/1` (ANSI + location header).
  # 5. Plain Elixir exceptions keep their message string as a last resort.
  alias Lua.VM.ArgumentError
  alias Lua.VM.AssertionError
  alias Lua.VM.TypeError

  def error_value(%{lua_value: lv}) when not is_nil(lv), do: lv
  def error_value(%TypeError{value: v} = e) when is_binary(v), do: positioned(v, e.line, e.source)
  def error_value(%AssertionError{value: v} = e) when is_binary(v), do: positioned(v, e.line, e.source)
  def error_value(%{value: value}), do: value
  def error_value(%ArgumentError{} = e), do: positioned(ArgumentError.raw_message(e), e.line, e.source)
  def error_value(e), do: Exception.message(e)

  @doc false
  # `message` prefixed with `source:line: `, or unchanged when the raise site
  # recorded no usable position (a wrong line is worse than none).
  def positioned(message, line, source) when is_integer(line) and line > 0 and is_binary(source),
    do: "#{source}:#{line}: #{message}"

  def positioned(message, _line, _source), do: message
end

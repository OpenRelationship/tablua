-- Unit cases for tablua.lexer: tokens that give the text back, a unit's columns, the names it uses, and a rename
-- that reaches references and never strings, comments or fields.
local spec = require("mono.spec")
local lexer = require("tablua.lexer")

local SRC = 'function post.add(form) return sum(form.a, form.b), "sum" end -- sum\nlocal x = 1e-3 .. [[sum]] .. t.sum\n'

spec.test("the tokens joined are the text", function()
  local parts = {}
  for i, tk in ipairs(lexer.tokens(SRC)) do parts[i] = tk.s end
  spec.eq(table.concat(parts), SRC)
  local long = "--[==[ a\n]] b ]==] x = 'it''s' y = 0x1p+4"
  parts = {}
  for i, tk in ipairs(lexer.tokens(long)) do parts[i] = tk.s end
  spec.eq(table.concat(parts), long)
end)

spec.test("a unit's columns: code lines, parameters, deepest block", function()
  spec.same(lexer.columns("-- adds\nlocal function sum(a, b, ...)\n  if a then return a + b end\nend\n"),
    { lines = 3, arity = 3, depth = 2 })
  spec.same(lexer.columns("local M = {}\n"), { lines = 1, arity = 0, depth = 0 })
  spec.same(lexer.columns("while x do\n  repeat y() until z\nend\n"), { lines = 3, arity = 0, depth = 2 })
end)

spec.test("the names a unit uses, dotted paths too, never fields or keywords", function()
  local refs = lexer.refs(SRC)
  spec.ok(refs.sum and refs.post and refs["post.add"] and refs.form and refs["form.a"] and refs.x)
  spec.ok(not refs.a and not refs["return"] and not refs["end"])
  spec.ok(refs.t and refs["t.sum"])
end)

spec.test("a rename reaches references, not strings, comments or another table's field", function()
  local out, n = lexer.rename(SRC, "sum", "plus")
  spec.eq(n, 1)
  spec.eq(out, 'function post.add(form) return plus(form.a, form.b), "sum" end -- sum\n'
    .. 'local x = 1e-3 .. [[sum]] .. t.sum\n')
  out, n = lexer.rename(SRC, "post.add", "post.plus")
  spec.eq(n, 1)
  spec.ok(out:find("function post.plus(form)", 1, true))
  spec.eq((lexer.rename("x = post .add", "post.add", "y")), "x = post .add")
end)

spec.run()

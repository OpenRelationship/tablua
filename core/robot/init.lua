-- Robot: an agent's tests in Robot Framework's syntax, parsed and run in portable Lua, every keyword's result kept
-- as a tree that becomes rows. Tests are keyword calls; a keyword is another list of calls, a Lua function in a
-- library, or one of BuiltIn's; Given, When, Then, And and But may lead a call, as in Robot.
--
--   local robot = require("robot")
--   local suite = robot.parse(text)                       robot.parse.cut(text) -> head, items (byte for byte)
--   local lib = robot.library() ; lib:add(name, fn)
--   local res = robot.run(suite, { libraries = { lib }, clock = os.clock })
--   robot.summary(res) -> { passed, total, undefined, failing = { { test, path, keyword, why, reach } } }
--   robot.rows(res) -> one row per keyword run
local parse = require("robot.parse")
local run = require("robot.run")
local result = require("robot.result")
local builtin = require("robot.builtin")

local M = {}

M.parse = setmetatable({ suite = parse.suite, cut = parse.cut, cells = parse.cells, header = parse.header },
  { __call = function(_, text) return parse.suite(text) end })
M.library = run.library
M.run = run.suite
M.summary = result.summary
M.rows = result.rows
M.norm = builtin.norm
M.embedded = run.embedded
M.captures = run.captures
M.builtin = builtin.keywords

-- whether a called name is a keyword of BuiltIn's
function M.is_builtin(name)
  if builtin.keywords[builtin.norm(name)] then return true end
  local first, rest = name:match("^(%a+)%s+(.+)$")
  return first and ({ given = 1, when = 1, ["then"] = 1, ["and"] = 1, but = 1 })[first:lower()]
    and builtin.keywords[builtin.norm(rest)] ~= nil or false
end

return M

-- A run's result (robot.run) read two ways: as a summary of what passed and how far each failing test got, and as
-- flat rows of its keyword tree, one per keyword, for a database.
--
--   result.summary(res) -> { passed, total, undefined = { name }, failing = { { test, path, keyword, why, reach } } }
--     path    the failing keyword's place in the tree ("2.1.3": the 2nd call of the test, its 1st, its 3rd)
--     reach   how many keywords passed in the test before it failed: a test that gets further reaches more
--   result.rows(res) -> { { test, path, parent, depth, type, keyword, args, status, message, ms, line } }
--     args are joined by tabs; a test's own row has path "" and type "test" (or "task", for a task's)
--   result.record(test, name?) -> text | nil, why
--     a passing test's run written as a task (*** Tasks ***): the keywords it called at its top level, in the order
--     they ran, with the values their arguments had, FOR and IF unrolled into the calls they made. Replayed, the task
--     does again what worked, with no model deciding. A value Robot would read as more than text (a variable, two
--     spaces, a tab) cannot be written as a cell, and the test is not recorded.
local M = {}

local function walk(nodes, prefix, depth, visit)
  for i, node in ipairs(nodes or {}) do
    local path = prefix == "" and tostring(i) or (prefix .. "." .. i)
    visit(node, path, prefix, depth)
    walk(node.children, path, depth + 1, visit)
  end
end

-- the setup's keywords, the body's, then the teardown's, as one list (setup and teardown named s and t)
local function tops(test)
  local out = {}
  if test.setup then out[#out + 1] = { node = test.setup, at = "s" } end
  for i, n in ipairs(test.body or {}) do out[#out + 1] = { node = n, at = tostring(i) } end
  if test.teardown then out[#out + 1] = { node = test.teardown, at = "t" } end
  return out
end

local function each(test, visit)
  for _, top in ipairs(tops(test)) do
    visit(top.node, top.at, "", 1)
    walk(top.node.children, top.at, 2, visit)
  end
end

function M.summary(res)
  local out = { passed = res.passed or 0, total = res.total or 0, undefined = {}, failing = {} }
  local seen = {}
  for _, t in ipairs(res.tests or {}) do
    local reach, deepest = 0, nil
    each(t, function(node, path, _, depth)
      if node.status == "PASS" and node.type == "keyword" then reach = reach + 1 end
      if node.undefined and not seen[node.name] then
        seen[node.name] = true
        out.undefined[#out.undefined + 1] = node.name
      end
      if node.status == "FAIL" and (not deepest or depth >= deepest.depth) then
        deepest = { path = path, keyword = node.name, why = node.message or "", depth = depth }
      end
    end)
    if t.status == "FAIL" then
      out.failing[#out.failing + 1] = { test = t.name, path = deepest and deepest.path or "",
        keyword = deepest and deepest.keyword or "", why = deepest and deepest.why or t.message or "", reach = reach }
    end
  end
  return out
end

function M.rows(res)
  local out = {}
  for _, t in ipairs(res.tests or {}) do
    out[#out + 1] = { test = t.name, path = "", parent = "", depth = 0, type = t.kind or "test", keyword = t.name,
      args = "",
      status = t.status, message = t.message or "", ms = t.ms or 0, line = t.line or 0 }
    each(t, function(node, path, parent, depth)
      out[#out + 1] = { test = t.name, path = path, parent = parent, depth = depth, type = node.type,
        keyword = node.name or "", args = table.concat(node.args or {}, "\t"), status = node.status,
        message = node.message or "", ms = node.ms or 0, line = node.line or 0 }
    end)
  end
  return out
end

-- one cell as written, or nil when Robot would read it as more than its text
local function cell(v)
  if v == "" then return "${EMPTY}" end
  if v:find("[%$@&%%]{") or v:find("  ") or v:find("[\t\n\r]") or v:find("\\") or v:match("^#")
    or v:match("^%.%.%.") or v:match("^%s") or v:match("%s$") then
    return nil
  end
  return v
end

-- a keyword node as the cells of a call: its name as called, then its arguments' values
local function call(node)
  local name = node.called or node.name
  if not cell(name) then return nil, ("the keyword name %q cannot be written as a cell"):format(name) end
  local cells = { name }
  for _, a in ipairs(node.args or {}) do
    local c = cell(a)
    if not c then return nil, ("%s's argument %q cannot be written as a cell"):format(name, a) end
    cells[#cells + 1] = c
  end
  return table.concat(cells, "    ")
end

function M.record(test, name)
  if test.status ~= "PASS" then return nil, "only a passing test is recorded: " .. test.name .. " " .. test.status end
  local out = { "*** Tasks ***", name or test.name }
  local function add(node, lead)
    local l, why = call(node)
    if not l then return nil, why end
    out[#out + 1] = "    " .. (lead and lead .. "    " or "") .. l
    return true
  end
  local function walk(nodes)
    for _, node in ipairs(nodes or {}) do
      local ok, why = true, nil
      if node.type == "keyword" then
        if node.status == "PASS" then ok, why = add(node) end
      elseif node.type ~= "return" then
        ok, why = walk(node.children)
      end
      if not ok then return nil, why end
    end
    return true
  end
  local ok, why = true, nil
  if test.setup then ok, why = add(test.setup, "[Setup]") end
  if ok then ok, why = walk(test.body) end
  if ok and test.teardown then ok, why = add(test.teardown, "[Teardown]") end
  if not ok then return nil, why end
  return table.concat(out, "\n") .. "\n"
end

return M

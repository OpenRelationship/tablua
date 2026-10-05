-- A run's result (robot.run) read two ways: as a summary of what passed and how far each failing test got, and as
-- flat rows of its keyword tree, one per keyword, for a database.
--
--   result.summary(res) -> { passed, total, undefined = { name }, failing = { { test, path, keyword, why, reach } } }
--     path    the failing keyword's place in the tree ("2.1.3": the 2nd call of the test, its 1st, its 3rd)
--     reach   how many keywords passed in the test before it failed: a test that gets further reaches more
--   result.rows(res) -> { { test, path, parent, depth, type, keyword, args, status, message, ms, line } }
--     args are joined by tabs; a test's own row has path "" and type "test"
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
    out[#out + 1] = { test = t.name, path = "", parent = "", depth = 0, type = "test", keyword = t.name, args = "",
      status = t.status, message = t.message or "", ms = t.ms or 0, line = t.line or 0 }
    each(t, function(node, path, parent, depth)
      out[#out + 1] = { test = t.name, path = path, parent = parent, depth = depth, type = node.type,
        keyword = node.name or "", args = table.concat(node.args or {}, "\t"), status = node.status,
        message = node.message or "", ms = node.ms or 0, line = node.line or 0 }
    end)
  end
  return out
end

return M

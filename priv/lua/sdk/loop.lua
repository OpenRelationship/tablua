-- loop: what `test` and `check` run on the computer (Arock feature file-kinds). The host calls it through
-- __loop (computer.lua) with a scope (/home, or /home/apps/<app>) and its files, and each result goes back to the
-- host through `report`, never through what is printed, so no step can say it passed.
--
--   loop.test(scope, features, report)   each feature run with the scope's steps (code/steps/**.lua):
--                                        report{ feature, passed, total, failing, undefined, broken }
--   loop.pages(scope, pages, report)     each page compiled: report{ page, why } (why nil when it compiles)
local test = require("test")
local lui = require("shroomi.lui")

-- held before any step file runs, so a step file that changes the test table changes no verdict
local run, clear = test.run, test.clear

local loop = {}

-- every .lua under dir, in name order
local function lua_files(dir, out)
  out = out or {}
  local names = fs.list(dir) or {}
  table.sort(names)
  for _, n in ipairs(names) do
    local p = dir .. "/" .. n
    if fs.isdir(p) then
      lua_files(p, out)
    elseif string.match(n, "%.lua$") then
      out[#out + 1] = p
    end
  end
  return out
end

local function load_steps(scope)
  clear()
  local broken = {}
  for _, p in ipairs(lua_files(scope .. "/code/steps")) do
    local chunk, why = load(fs.read(p) or "", "@" .. p)
    if chunk then
      local ok, err = pcall(chunk)
      if not ok then broken[#broken + 1] = p .. ": " .. tostring(err) end
    else
      broken[#broken + 1] = why
    end
  end
  return broken
end

function loop.test(scope, features, report)
  local broken = load_steps(scope)
  for _, f in ipairs(broken) do print("# a step file does not load: " .. f) end
  for _, f in ipairs(features) do
    print("# " .. (string.gsub(f, "^/home/", "")))
    local text = fs.read(f) or ""
    local ok, all, passed, total, r = pcall(run, text, f)
    if not ok then
      print("# " .. f .. " does not run: " .. tostring(all))
      r, passed, total = { failing = { { step = "", why = tostring(all) } }, undefined = {} }, 0, 0
    end
    report({ feature = f, passed = passed, total = total, failing = r.failing, undefined = r.undefined,
      broken = broken })
  end
end

function loop.pages(_, pages, report)
  for _, p in ipairs(pages) do
    local _, why = lui.compile(fs.read(p) or "", p)
    report({ page = p, why = why })
  end
end

return loop

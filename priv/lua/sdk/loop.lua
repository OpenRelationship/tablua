-- loop: what `test` and `check` run on the computer (Arock feature file-kinds). The host calls it through
-- __loop (computer.lua) with a scope (/home, or /home/apps/<app>) and its files, and each result goes back to the
-- host through `report`, never through what is printed, so no step can say it passed.
--
--   loop.test(scope, features, report)   each feature run with the scope's steps (code/steps/**.lua):
--                                        report{ feature, passed, total, failing, undefined, broken }
--   loop.pages(scope, pages, report)     each page compiled: report{ page, why } (why nil when it compiles)
local test = require("test")
local lui = require("shroomi.lui")
local browse = require("browse")

-- held before any step file runs, so a step file that changes the test table changes no verdict
local run, clear, locate, own = test.run, test.clear, test.locate, test.own
local clear_data = db.clear_scratch

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
  -- the page's own steps come first, so a step file cannot answer for the page (sdk/browse.lua)
  browse.install(test, scope)
  own("the page's, sdk/browse.lua")
  local broken = {}
  for _, p in ipairs(lua_files(scope .. "/code/steps")) do
    local text = fs.read(p) or ""
    local chunk, why = load(text, "@" .. p)
    if chunk then
      local ok, err = pcall(chunk)
      -- the VM's message carries the file and line when it knows them; the file is named either way
      if not ok then
        err = tostring(err)
        broken[#broken + 1] = string.find(err, p, 1, true) and err or (p .. ": " .. err)
      end
      for _, shadow in ipairs(locate(p, text)) do broken[#broken + 1] = shadow end
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
    local ok, all, passed, total, r = pcall(run, text, f, clear_data)
    if not ok then
      print("# " .. f .. " does not run: " .. tostring(all))
      r, passed, total = { failing = { { step = "", why = tostring(all) } }, undefined = {}, checked = {} }, 0, 0
    end
    report({ feature = f, passed = passed, total = total, failing = r.failing, undefined = r.undefined,
      checked = r.checked, broken = broken })
  end
end

function loop.pages(_, pages, report)
  for _, p in ipairs(pages) do
    local why
    if p:match("%.org$") then why = require("orgpage").check(fs.read(p) or "", p)
    else why = select(2, lui.compile(fs.read(p) or "", p)) end
    report({ page = p, why = why })
  end
end

return loop

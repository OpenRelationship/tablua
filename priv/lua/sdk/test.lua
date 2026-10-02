-- test: Gherkin features run by Lua steps, written out as Robot rows.
--
--   local test = require("test")
--   test.step("the list holds {int} items", function(w, n) test.eq(#w.items, n) end)
--   test.run_file("features/todo.feature")    -- or test.run(text, name); true when every scenario passed
--   test.eq(got, want [, what]), test.ok(v [, what])   fail the step unless they hold
--
-- A step's pattern matches the step's text after Given/When/Then/And/But, with {int}, {number}, {string}
-- ("quoted"), {word} and {} (anything) as its holes. Its function gets the scenario's world (a fresh table per
-- scenario, which Background steps share) and the holes, then a doc string or a data table (a list of rows)
-- if the step has one. Scenario Outlines run once per Examples row, <name> filled in.
--
-- The run is printed as Robot Framework rows: one test per scenario, one row per step, its result in the row
-- (PASS, FAIL and why, or NOT RUN). A step no pattern matches fails, and the run prints the Lua stub to paste
-- into code/steps/ (test.stub). The last line counts what passed. test.run also returns what failed:
-- { failing = { { scenario, step, why } }, undefined = { text } }.
local test = {}

local defined = {}

local HOLES = {
  ["{int}"] = { "(%-?%d+)", tonumber },
  ["{number}"] = { "(%-?%d+%.?%d*)", tonumber },
  ["{string}"] = { "\"([^\"]*)\"", nil },
  ["{word}"] = { "([^%s]+)", nil },
  ["{}"] = { "(.-)", nil },
}

function test.step(pattern, fn)
  local lua, casts, at = { "^" }, {}, 1
  while at <= #pattern do
    local s, e = string.find(pattern, "{%a*}", at)
    local literal = string.sub(pattern, at, (s or #pattern + 1) - 1)
    lua[#lua + 1] = (string.gsub(literal, "[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
    if not s then break end
    local hole = HOLES[string.sub(pattern, s, e)]
    if not hole then error("test: no such hole " .. string.sub(pattern, s, e), 2) end
    lua[#lua + 1] = hole[1]
    casts[#casts + 1] = hole[2] or false
    at = e + 1
  end
  lua[#lua + 1] = "$"
  defined[#defined + 1] = { text = pattern, lua = table.concat(lua), casts = casts, fn = fn }
end

function test.clear() defined = {} end

local function show(v)
  if type(v) == "string" then return string.format("%q", v) end
  return tostring(v)
end

function test.eq(got, want, what)
  if got ~= want then error((what and what .. ": " or "") .. "wanted " .. show(want) .. ", got " .. show(got), 2) end
end

function test.ok(v, what)
  if not v then error(what or "not true", 2) end
  return v
end

-- the feature as scenarios of steps
local function parse(text)
  local feature, background, scenarios = nil, {}, {}
  local current, step, outline = nil, nil, nil
  local lines = {}
  for line in string.gmatch(string.gsub(text, "\r\n?", "\n") .. "\n", "(.-)\n") do lines[#lines + 1] = line end
  local i = 1
  while i <= #lines do
    local line = string.match(lines[i], "^%s*(.-)%s*$")
    local key, rest = string.match(line, "^(%a[%a ]*):%s*(.*)$")
    if line == "" or string.sub(line, 1, 1) == "#" or string.sub(line, 1, 1) == "@" then
      -- nothing
    elseif string.sub(line, 1, 3) == '"""' then
      local doc, indent = {}, #string.match(lines[i], "^(%s*)")
      i = i + 1
      while i <= #lines and not string.match(lines[i], '^%s*"""') do
        doc[#doc + 1] = string.sub(lines[i], indent + 1)
        i = i + 1
      end
      if step then step.extra = table.concat(doc, "\n") end
    elseif string.sub(line, 1, 1) == "|" then
      local row = {}
      for cell in string.gmatch(string.sub(line, 2), "([^|]*)|") do row[#row + 1] = string.match(cell, "^%s*(.-)%s*$") end
      if outline and outline.examples then
        outline.examples[#outline.examples + 1] = row
      elseif step then
        step.extra = type(step.extra) == "table" and step.extra or {}
        step.extra[#step.extra + 1] = row
      end
    elseif key == "Feature" then
      feature = rest
    elseif key == "Background" then
      current, outline = background, nil
    elseif key == "Scenario" or key == "Example" then
      local sc = { name = rest, steps = {} }
      scenarios[#scenarios + 1] = sc
      current, outline = sc.steps, nil
    elseif key == "Scenario Outline" or key == "Scenario Template" then
      outline = { name = rest, steps = {} }
      scenarios[#scenarios + 1] = outline
      current = outline.steps
    elseif key == "Examples" or key == "Scenarios" then
      if outline then outline.examples = {} end
    else
      local word, body = string.match(line, "^(%a+)%s+(.*)$")
      if current and ({ Given = 1, When = 1, Then = 1, And = 1, But = 1 })[word] then
        step = { word = word, text = body }
        current[#current + 1] = step
      end
    end
    i = i + 1
  end
  -- outlines become one scenario per Examples row
  local out = {}
  for _, sc in ipairs(scenarios) do
    if sc.examples then
      local head = sc.examples[1] or {}
      for r = 2, #sc.examples do
        local row, steps = sc.examples[r], {}
        local function fill(s) return (string.gsub(s, "<([^>]+)>", function(k)
          for c, name in ipairs(head) do if name == k then return row[c] end end
        end)) end
        for _, s in ipairs(sc.steps) do
          steps[#steps + 1] = { word = s.word, text = fill(s.text), extra = type(s.extra) == "string" and fill(s.extra) or s.extra }
        end
        out[#out + 1] = { name = fill(sc.name) .. " (" .. table.concat(row, ", ") .. ")", steps = steps }
      end
    else
      out[#out + 1] = sc
    end
  end
  return feature, background, out
end

local function find(text)
  for _, d in ipairs(defined) do
    local caps = { string.match(text, d.lua) }
    if caps[1] ~= nil then
      local args = {}
      for k, cast in ipairs(d.casts) do args[k] = cast and cast(caps[k]) or caps[k] end
      return d, args
    end
  end
end

-- a Robot cell, escaped as alog.robot escapes one
local function cell(v)
  v = tostring(v)
  if v == "" then return "\\" end
  v = string.gsub(v, "\\", "\\\\")
  v = string.gsub(v, "\n", "\\n")
  v = string.gsub(v, "\t", "\\t")
  v = string.gsub(v, "  ", " \\x20")
  v = string.gsub(v, "^ ", "\\x20")
  v = string.gsub(v, " $", "\\x20")
  v = string.gsub(v, "([%$@&%%]){", "\\%1{")
  return v
end

-- the step to paste for text no step matches: quoted words become {string}, numbers {int} or {number}
function test.stub(text)
  local out, args, i = {}, {}, 1
  while i <= #text do
    local c = string.sub(text, i, i)
    local close = c == '"' and string.find(text, '"', i + 1, true)
    local num = not close and (i == 1 or not string.find(string.sub(text, i - 1, i - 1), "[%w_]"))
      and (string.match(text, "^%-?%d+%.%d+", i) or string.match(text, "^%-?%d+", i))
    if close then
      out[#out + 1], args[#args + 1], i = "{string}", "s" .. (#args + 1), close + 1
    elseif num then
      out[#out + 1] = string.find(num, ".", 1, true) and "{number}" or "{int}"
      args[#args + 1], i = "n" .. (#args + 1), i + #num
    else
      out[#out + 1], i = c, i + 1
    end
  end
  local params = #args > 0 and "w, " .. table.concat(args, ", ") or "w"
  return string.format('test.step(%q, function(%s)\n  error("not written yet")\nend)', table.concat(out), params)
end

local function run_steps(steps, world, rows, failed, report)
  for _, s in ipairs(steps) do
    local text = s.word .. " " .. s.text
    if failed then
      rows[#rows + 1] = { text, "NOT RUN" }
    else
      local d, args = find(s.text)
      if not d then
        failed = "no step matches: " .. s.text
        rows[#rows + 1] = { text, "FAIL", failed }
        report.undefined[#report.undefined + 1] = s.text
      else
        if s.extra ~= nil then args[#args + 1] = s.extra end
        local ok, why = pcall(d.fn, world, table.unpack(args))
        if ok then
          rows[#rows + 1] = { text, "PASS" }
        else
          failed = tostring(why)
          rows[#rows + 1] = { text, "FAIL", failed }
          report.failing[#report.failing + 1] = { step = text, why = failed }
        end
      end
    end
  end
  return failed
end

function test.run(text, name)
  local feature, background, scenarios = parse(text)
  local lines, passed = { "*** Test Cases ***" }, 0
  local report = { failing = {}, undefined = {} }
  for _, sc in ipairs(scenarios) do
    local rows, world = {}, {}
    local before = #report.failing
    local failed = run_steps(background, world, rows, nil, report)
    failed = run_steps(sc.steps, world, rows, failed, report)
    for k = before + 1, #report.failing do report.failing[k].scenario = sc.name end
    if not failed then passed = passed + 1 end
    lines[#lines + 1] = cell(sc.name)
    for _, r in ipairs(rows) do
      local cells = {}
      for k, v in ipairs(r) do cells[k] = cell(v) end
      lines[#lines + 1] = "    " .. table.concat(cells, "    ")
    end
  end
  print(table.concat(lines, "\n"))
  local seen = {}
  for _, text in ipairs(report.undefined) do
    local stub = test.stub(text)
    if not seen[stub] then
      seen[stub] = true
      print("# no step matches \"" .. text .. "\"; paste this into code/steps/ and write it:\n" .. stub)
    end
  end
  print(string.format("# %s: %d of %d scenarios passed", feature or name or "feature", passed, #scenarios))
  return passed == #scenarios, passed, #scenarios, report
end

function test.run_file(path)
  local text, why = fs.read(path)
  if not text then error("test: " .. path .. ": " .. tostring(why), 2) end
  return test.run(text, path)
end

return test

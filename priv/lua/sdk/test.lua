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

-- Where the steps a file just defined live (its loader calls this with the file's text): each pattern's line, found by
-- its text, so a near miss can say where the step it nearly matched is.
function test.locate(path, text)
  for _, d in ipairs(defined) do
    if not d.at then
      local s = string.find(text, d.text, 1, true)
      local line = 1
      if s then for _ in string.gmatch(string.sub(text, 1, s), "\n") do line = line + 1 end end
      d.at = string.gsub(path, "^/home/", "") .. (s and (":" .. line) or "")
    end
  end
end

-- a line's words, a "quoted" string one word; a pattern's holes stay words of their own
local function words(s)
  local out, i = {}, 1
  while i <= #s do
    local a, b = string.find(s, '^"[^"]*"', i)
    if not a then a, b = string.find(s, "^[^%s]+", i) end
    if a then out[#out + 1], i = string.sub(s, a, b), b + 1 else i = i + 1 end
  end
  return out
end

local FITS = {
  ["{string}"] = function(w) return string.match(w, '^".*"$') end,
  ["{int}"] = function(w) return string.match(w, "^%-?%d+$") end,
  ["{number}"] = function(w) return string.match(w, "^%-?%d+%.?%d*$") end,
  ["{word}"] = function(w) return not string.find(w, '"', 1, true) end,
  ["{}"] = function() return true end,
}

-- why a line no step matches nearly matched one: the nearest pattern of as many words, where it is, and each word
-- that kept them apart
function test.nearest(text)
  local tw, best, score = words(text), nil, 0
  for _, d in ipairs(defined) do
    local pw = words(d.text)
    if #pw == #tw then
      local same = 0
      for k = 1, #pw do if pw[k] == tw[k] or (FITS[pw[k]] and FITS[pw[k]](tw[k])) then same = same + 1 end end
      if same / #pw > score then best, score = d, same / #pw end
    end
  end
  if not best or score < 0.75 then return nil end
  local pw, why = words(best.text), {}
  for k = 1, #pw do
    local fits = FITS[pw[k]]
    if fits and not fits(tw[k]) then
      if pw[k] == "{string}" then
        why[#why + 1] = ('{string} takes "quoted" text and the line has %s: use {word} for one bare word'):format(tw[k])
      else
        why[#why + 1] = ("%s does not take %s"):format(pw[k], tw[k])
      end
    elseif not fits and pw[k] ~= tw[k] then
      why[#why + 1] = ('the step says "%s" where the line says "%s"'):format(pw[k], tw[k])
    end
  end
  return ("nearest: %q%s: %s"):format(best.text, best.at and (" at " .. best.at) or "", table.concat(why, "; "))
end

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

-- a Robot cell, escaped as arock-log.robot escapes one
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
        local near = test.nearest(s.text)
        failed = "no step matches: " .. s.text .. (near and (" (" .. near .. ")") or "")
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

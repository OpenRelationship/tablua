-- The change block's operations on the tests (tablua.change): a test, a task or a user keyword of the tests
-- section, by name, added, replaced or removed (%% test, %% task, %% keyword), with each run of a kind under its own
-- header. A new one goes after the last of its kind; the first of a kind goes in the order tests, tasks, keywords.
--   require("tablua.change_tests")(DO, { recut, op_line })   adds DO.test, DO.task and DO.keyword
local src = require("tablua.source")

return function(DO, h)
  local recut, op_line = h.recut, h.op_line

  -- Tests and user keywords: one item of the tests section, by name -------------------------------------------------

  local HEADER = { test = "*** Test Cases ***\n", task = "*** Tasks ***\n", keyword = "*** Keywords ***\n" }
  local ORDER = { test = 1, task = 2, keyword = 3 }

  -- the section's items with their headers made again: one before the first item of each run of a kind, and none
  -- left in the head, so moving or removing an item never strands a header or leaves one out
  local function regroup(s)
    s.head = (s.head or ""):gsub("\n?%*%*%*%s*[TtKk][^\n]*%*%*%*%s*\n?$", function(m) return m:sub(1, 1) == "\n" and "\n" or "" end)
    local prev
    for _, it in ipairs(s.items) do
      local text = it.text
      while text:match("^%*%*%*[^\n]*\n") do text = text:gsub("^%*%*%*[^\n]*\n", "", 1) end
      if it.kind ~= prev then text = HEADER[it.kind] .. text end
      it.text, prev = text, it.kind
    end
    for i = 2, #s.items do
      local a, b = s.items[i - 1], s.items[i]
      if a.kind ~= b.kind and not a.text:match("\n\n$") then a.text = a.text .. "\n" end
    end
  end

  local function item_op(kind)
    return function(rows, op)
      local s
      for _, x in ipairs(rows.sections) do if x.kind == "tests" then s = x end end
      if not s then
        s = { kind = "tests", head = "", items = {} }
        local at = #rows.sections + 1
        for i, other in ipairs(rows.sections) do
          if other.kind ~= "notes" then at = i break end
        end
        table.insert(rows.sections, at, s)
      end
      local k
      for i, it in ipairs(s.items) do if it.kind == kind and it.name == op.name then k = i end end
      local old = k and s.items[k]
      local function strip(text) return (text:gsub("^%*%*%*[^\n]*\n", "")) end
      if op.body == "" then
        if not old then return nil, ("operation %d names no %s %q"):format(op.n, kind, op.name) end
        table.remove(s.items, k)
        regroup(s)
        recut(s)
        local prev = s.items[k - 1]
        local where_ = prev and (" after " .. prev.name) or " first"
        return op_line(kind .. "!", op.name, where_) .. strip(old.text), kind, #src.calls(old), 0
      end
      local _, list = src.tests(HEADER[kind] .. op.body)
      if #list ~= 1 or list[1].name ~= op.name or list[1].kind ~= kind then
        return nil, ("operation %d: its text should be the one %s %q"):format(op.n, kind, op.name)
      end
      local new = { kind = kind, name = op.name, text = strip(list[1].text) }
      if old then
        s.items[k] = new
      else
        local at
        if op.first then at = 1
        elseif op.after then
          for i, it in ipairs(s.items) do if it.name == op.after then at = i + 1 end end
          if not at then return nil, ("operation %d names no test, task or keyword %q"):format(op.n, op.after) end
        else
          -- after the last of its kind; the first of a kind before every item of a kind that comes after it
          for i, it in ipairs(s.items) do if it.kind == kind then at = i + 1 end end
          if not at then
            at = #s.items + 1
            for i, it in ipairs(s.items) do if ORDER[it.kind] > ORDER[kind] then at = i break end end
          end
        end
        table.insert(s.items, at, new)
      end
      regroup(s)
      recut(s)
      local undo = old and op_line(kind .. "!", op.name) .. strip(old.text) or op_line(kind, op.name)
      return undo, kind, old and #src.calls(old) or 0, #src.calls(new)
    end
  end


  DO.test = item_op("test")
  DO.task = item_op("task")
  DO.keyword = item_op("keyword")
end

-- Edits to one unit at a time (arock issue #1 M6b), for a run that edits rows (run.edits "rows", AROCK_EDITS in
-- Arock's eval) against one that writes files whole: the filler's computer call may carry edits, each naming a
-- file, one of its units and the unit's new source, and the harness splices each into the file's rows
-- (tablua.edit) and writes the file whole itself. What an edit could name is listed with the move, read from the
-- app's files; an edit that would not compile, or names a file it cannot change, is refused and said, and the
-- call's command then does not run.
--
--   edits.on(run) -> bool                     edits.tool(base) -> the computer tool with its edits property
--   edits.index(host) -> text                 the units each of the app's files holds, for the move's text
--   edits.apply(host, call) -> problems       the call's edits made into its files (call.edits cleared), or why not
--   call.applied -> { { file, unit, bytes } } what was spliced, for Tablua's action rows (world/record.lua)
local edit = require("tablua.edit")

local M = {}

function M.on(run) return run ~= nil and run.edits == "rows" end

local function quote(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

function M.tool(base)
  local f = base["function"]
  local props = {}
  for k, v in pairs(f.parameters.properties) do props[k] = v end
  props.edits = { type = "array", description = "Changes to one unit of a file each, made before the command runs:"
    .. " the file (relative to /home: code/x.lua, code/steps/x.lua or a page ui/x.org), the unit's name as the move"
    .. " lists them (post.add, a function's or a local's name, a step's text, or page for a page's * Page), and the"
    .. " unit's whole new source. A unit the file does not have yet is added at its end. Prefer an edit to writing"
    .. " the whole file when one unit is wrong.",
    items = { type = "object", required = { "file", "unit", "source" }, properties = {
      file = { type = "string" }, unit = { type = "string" }, source = { type = "string" } } } }
  return { type = base.type, ["function"] = { name = f.name, strict = f.strict,
    description = f.description .. " Edits change one unit of a file each, written before the files and the command.",
    parameters = { type = "object", required = f.parameters.required, properties = props } } }
end

function M.index(host)
  local r = host.exec({ cmd = "find code ui" })
  local lines = {}
  for path in tostring(r.stdout or ""):gmatch("[^\n]+") do
    path = path:gsub("^%./", "")
    if path:match("%.lua$") or path:match("^ui/.+%.org$") then
      local c = host.exec({ cmd = "cat " .. quote(path) })
      local names = c.code == 0 and edit.index(path, c.stdout or "") or {}
      if #names > 0 then lines[#lines + 1] = path .. ": " .. table.concat(names, ", ") end
    end
  end
  table.sort(lines)
  if #lines == 0 then return "" end
  return "\nThe units an edit can name, by file:\n" .. table.concat(lines, "\n")
end

function M.apply(host, call)
  local problems, texts = {}, {}
  call.applied = {}
  for _, e in ipairs(type(call.edits) == "table" and call.edits or {}) do
    local file = tostring(e.file or ""):gsub("^/home/", ""):gsub("^%./", "")
    local text = (call.files or {})[file] or texts[file]
    if text == nil then
      local c = host.exec({ cmd = "cat " .. quote(file) })
      text = c.code == 0 and (c.stdout or "") or false
    end
    local out, why = edit.apply(file, text or nil, e.unit, e.source)
    if out then
      texts[file] = out
      call.applied[#call.applied + 1] = { file = file, unit = tostring(e.unit), bytes = #tostring(e.source or "") }
    else
      problems[#problems + 1] = ("edit %s in %s: %s"):format(tostring(e.unit), file, why)
    end
  end
  call.edits = nil
  if next(texts) then
    call.files = call.files or {}
    for file, text in pairs(texts) do call.files[file] = text end
  end
  return problems
end

return M

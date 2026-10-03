-- The files a change is about to write, as they were before it (world.lua): when the change breaks scenarios that
-- passed, Jev is offered undo, and these go back as they were (a file the change made is removed). The computer has
-- no undo of its own, so the world keeps the last change's files itself, read and written through host.exec.
--
--   local kept = undo.keep(host, calls)     before the calls run: { { cwd, path, text | false } }
--   undo.restore(host, kept) -> lines       each file put back, or removed when the change made it
local M = {}

local function quote(s) return "'" .. tostring(s):gsub("'", "'\\''") .. "'" end

function M.keep(host, calls)
  local kept, seen = {}, {}
  for _, c in ipairs(calls) do
    for path in pairs(c.files or {}) do
      local key = (c.cwd or "") .. "\n" .. path
      if not seen[key] then
        seen[key] = true
        local r = host.exec({ cmd = "cat " .. quote(path), cwd = c.cwd })
        kept[#kept + 1] = { cwd = c.cwd, path = path, text = r.code == 0 and (r.stdout or "") or false }
      end
    end
  end
  table.sort(kept, function(a, b) return a.path < b.path end)
  return kept
end

function M.restore(host, kept)
  local lines = {}
  for _, k in ipairs(kept) do
    local r
    if k.text then
      r = host.exec({ cmd = "true", cwd = k.cwd, files = { [k.path] = k.text } })
      lines[#lines + 1] = ("put back %s  -> %d"):format(k.path, r.code)
    else
      r = host.exec({ cmd = "rm " .. quote(k.path), cwd = k.cwd })
      lines[#lines + 1] = ("removed %s (the change made it)  -> %d"):format(k.path, r.code)
    end
  end
  return lines
end

return M

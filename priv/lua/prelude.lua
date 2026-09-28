-- require over the module sources the host put in __sources, since the
-- sandbox has no filesystem and no package library. A module is loaded once
-- per state; the host keeps a base state with the core already loaded.
local sources, loaded = __sources, {}

function require(name)
  local v = loaded[name]
  if v ~= nil then return v end
  local src = sources[name] or error("module " .. name .. " not found", 2)
  local f = assert(load(src, "=" .. name))
  v = f(name)
  if v == nil then v = true end
  loaded[name] = v
  return v
end

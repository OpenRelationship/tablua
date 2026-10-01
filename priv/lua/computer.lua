-- The computer's library for a Lua run (Moss.Computer.Script): what a script can reach, all of it this
-- computer's own. __sys holds the host's functions; everything here is plain Lua over them.
--
--   print(...), io.write(...), io.read("a" | "l" | "n"), io.lines(), io.stderr:write(...)
--   arg[0] the script, arg[1]... its args; os.time(), os.clock(), os.date(), os.exit(n)
--   fs.read(path), fs.write(path, s), fs.append(path, s), fs.list(path), fs.mkdir(path),
--   fs.remove(path [, all]), fs.rename(a, b), fs.exists(path), fs.isdir(path), fs.cwd()
--   http.get(url [, headers]), http.post(url, body [, headers]), http.request{ method, url, headers, body }
--   json.encode(v), json.decode(s)
--   mail.send(to, subject, body)
--   require("name"): name.lua or name/init.lua in the working folder, then /home/lib
-- A failure returns nil and why, as Lua's own io does.
local sys = __sys
debug = { traceback = debug.traceback }
__sys = nil

local function tostr(...)
  local n, parts = select("#", ...), {}
  for i = 1, n do parts[i] = tostring((select(i, ...))) end
  return table.concat(parts, "\t")
end

function print(...) sys.write(tostr(...) .. "\n") end

-- stdin, read as the command's whole input
local input, at = sys.stdin() or "", 1
local function read_line(keep)
  if at > #input then return nil end
  local nl = string.find(input, "\n", at, true)
  local line = string.sub(input, at, nl and nl - 1 or #input)
  at = (nl or #input) + 1
  return keep and nl and line .. "\n" or line
end

io = {
  write = function(...) for i = 1, select("#", ...) do sys.write(tostring((select(i, ...)))) end return io end,
  read = function(how)
    how = string.gsub(tostring(how or "l"), "^%*", "")
    if how == "a" then local s = string.sub(input, at) at = #input + 1 return s end
    if how == "L" then return read_line(true) end
    if how == "n" then local l = read_line() return l and tonumber(l) end
    return read_line()
  end,
  lines = function() return read_line end,
  stderr = { write = function(self, ...) for i = 1, select("#", ...) do sys.ewrite(tostring((select(i, ...)))) end return self end },
}
io.stdout = { write = function(self, ...) io.write(...) return self end }

local exit = {}
os.exit = function(n) error(setmetatable({ code = n == false and 1 or tonumber(n) or 0 }, exit), 0) end
os.time = os.time or function() return math.floor(sys.now()) end
os.clock = function() return sys.now() end

fs = {
  read = sys.read, mkdir = sys.mkdir, rename = sys.rename, cwd = sys.cwd,
  write = function(p, s) return sys.write_file(p, s) end,
  append = function(p, s) local old = sys.read(p) or "" return sys.write_file(p, old .. s) end,
  list = function(p) return sys.list(p or ".") end,
  remove = function(p, all) return sys.remove(p, all == true) end,
  exists = function(p) return sys.stat(p) ~= nil end,
  isdir = function(p) return sys.stat(p) == true end,
}

http = {
  request = sys.http,
  get = function(url, headers) return sys.http({ method = "GET", url = url, headers = headers }) end,
  post = function(url, body, headers) return sys.http({ method = "POST", url = url, body = body, headers = headers }) end,
}

json = { encode = sys.json_encode, decode = sys.json_decode }
mail = { send = sys.mail }

-- require, from the disk: the working folder first, then /home/lib
local loaded = {}
function require(name)
  if loaded[name] ~= nil then return loaded[name] end
  local rel = string.gsub(name, "%.", "/")
  for _, p in ipairs({ rel .. ".lua", rel .. "/init.lua", "/home/lib/" .. rel .. ".lua", "/home/lib/" .. rel .. "/init.lua" }) do
    local src = sys.read(p)
    if src then
      local chunk, why = load(src, "@" .. p)
      if not chunk then error(why, 2) end
      local v = chunk(name)
      if v == nil then v = true end
      loaded[name] = v
      return v
    end
  end
  error("module '" .. name .. "' not found (looked in the working folder and /home/lib)", 2)
end

-- The run: the code under xpcall; an error is written to stderr and is status 1, os.exit(n) is status n.
-- tv-labs lua names every chunk "-no-source-", so the message is given the script's name here.
function __main(code, name)
  arg = { [0] = name }
  for i, v in ipairs(__args or {}) do arg[i] = v end
  __args = nil
  local function say(e)
    e = string.gsub(tostring(e), "^%-no%-source%-", function() return name end)
    sys.ewrite("lua: " .. e .. "\n")
    return 1
  end
  local chunk, why = load(code, "@" .. name)
  if not chunk then return say(why) end
  local ok, e = xpcall(chunk, function(e)
    if getmetatable(e) == exit then return e end
    return tostring(e)
  end, table.unpack(arg))
  if ok then return 0 end
  if getmetatable(e) == exit then return e.code end
  return say(e)
end

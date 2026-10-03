-- Lua on this computer: `lua file.lua [args]` or `lua -e '<code>'`. A script reaches this computer's own files,
-- the public web, mail along the routes its person set, and nothing else. A run stops past 500 million
-- instructions, 64 MB of memory, 120 s or 1 MB of output.
--
--   print(...), io.write(...), io.read("a" | "l" | "n"), io.lines(), io.stderr:write(...)
--   arg[0] the script, arg[1]... its args; os.time(), os.clock(), os.date(), os.exit(n)
--   fs.read(path), fs.write(path, s), fs.append(path, s), fs.list(path), fs.mkdir(path),
--   fs.remove(path [, all]), fs.rename(a, b), fs.exists(path), fs.isdir(path), fs.cwd()
--   http.get(url [, headers]), http.post(url, body [, headers]), http.request{ method, url, headers, body }
--   json.encode(v), json.decode(s)
--   mail.send(to, subject, body)
--   db.open("data/plants.dbl") -> d; d:exec(sql, ...), d:query(sql, ...) -> rows, d:one(sql, ...) (`help data`)
--   date, csv and test are at hand; require("name"): the library's modules (`help lua`), then name.lua or
--     name/init.lua in the working folder, then the app's code/, then /home/code/
--   Pages are ui/*.lui (`help page`); a tool is code named in manifest.org (`help manifest`).
-- A failure returns nil and why, as Lua's own io does; a database statement that fails raises, with its file and line.

-- (Moss.Computer.Script binds __sys, the host's functions; everything here is plain Lua over them.)
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

-- params as a list SQLite binds in order; nil goes as false, which binds as NULL
local function params(...)
  local t = {}
  for i = 1, select("#", ...) do
    local v = select(i, ...)
    if v == nil then v = false end
    t[i] = v
  end
  return t
end

local Db = {}
Db.__index = Db
-- a statement that fails stops the code that ran it, with its file and line: a page whose insert named a column
-- the table lacks answered 200 and kept nothing (a chores run), where it now answers 500 and says why
local function run(self, sql, ...)
  local rows, changes = sys.db_exec(self.h, sql, params(...))
  if rows == nil then error(changes, 3) end
  return rows, changes
end
function Db:exec(sql, ...) return select(2, run(self, sql, ...)) end
function Db:query(sql, ...) return (run(self, sql, ...)) end
function Db:one(sql, ...) return run(self, sql, ...)[1] end
function Db:save() return sys.db_save(self.h) end
function Db:close() return sys.db_close(self.h) end

db = {
  open = function(path)
    local h, why = sys.db_open(path)
    if h == nil then return nil, why end
    return setmetatable({ h = h, path = path }, Db)
  end,
}

-- require, from the disk: the working folder first, then the app's code/ (when the run is in an app), then
-- /home/code/ (Arock's feature file-kinds: code lives in code/)
local loaded = {}
function require(name)
  if loaded[name] ~= nil then return loaded[name] end
  local own = sys.module(name)
  if own then
    local v = load(own, "@" .. name .. ".lua")(name)
    loaded[name] = v
    return v
  end
  local rel = string.gsub(name, "%.", "/")
  local roots = { "" }
  local app = string.match(sys.cwd() or "", "^(/home/apps/[%w%-]+)")
  if app then roots[#roots + 1] = app .. "/code/" end
  roots[#roots + 1] = "/home/code/"
  local tries = {}
  for _, root in ipairs(roots) do
    tries[#tries + 1] = root .. rel .. ".lua"
    tries[#tries + 1] = root .. rel .. "/init.lua"
  end
  for _, p in ipairs(tries) do
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
  error("module '" .. name .. "' not found (looked in the working folder, the app's code/ and /home/code/)", 2)
end

-- date, csv and test at hand, as db and json are: loaded the first time a script names them (require works too)
setmetatable(_G, { __index = function(g, name)
  if name == "date" or name == "csv" or name == "test" then
    local m = require(name)
    rawset(g, name, m)
    return m
  end
end })

-- The run: the code under xpcall; an error is written to stderr and is status 1, os.exit(n) is status n.
function __main(code, name)
  arg = { [0] = name }
  for i, v in ipairs(__args or {}) do arg[i] = v end
  -- a tool's arguments by name too, typed as its manifest declares (arg.city, arg.days)
  for k, v in pairs(__named or {}) do arg[k] = v end
  __args, __named = nil, nil
  local function say(e)
    sys.ewrite("lua: " .. tostring(e) .. "\n")
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

-- A request (Moss.Computer.App): the .lui page that answers its path (req.page, chosen by Moss.Computer.Pages, run in
-- its app's folder), given { method, path, query = {k = v}, form = {k = v}, headers }; it answers with HTML text,
-- or { status, body, headers, redirect }.
local function say(e)
  e = tostring(e)
  sys.ewrite("app: " .. e .. "\n")
  return e
end

local function reply(res)
  if type(res) == "string" then return 200, {}, res end
  if type(res) ~= "table" then return 500, {}, "The app answered with no page." end
  if res.redirect then return 303, { location = res.redirect }, "" end
  return tonumber(res.status) or 200, res.headers or {}, tostring(res.body or "")
end

-- a page is compiled once for its name and text, and the node keeps what it compiled to (sys.compiled)
local function page(req)
  local name = string.gsub(req.page, "^/home/", "")
  -- the computer's own look asks where each element is written (Moss.Computer.Look); the page never sees it
  local lines = req.lines == true
  req.lines = nil
  local ok, res = xpcall(function()
    local lui, text = require("shroomi.lui"), sys.read(req.page)
    local src = sys.compiled(name, text)
    if not src then
      src = lui.compile(text, name)
      if src then sys.compiled(name, text, src) end
    end
    return lui.answer(text, name, req, src, { lines = lines })
  end, tostring)
  if not ok then return 500, {}, "The page failed: " .. say(res) end
  return reply(res)
end

-- The loop (Arock feature file-kinds): `test` and `check` run here (sdk/loop.lua), each result handed to the host
-- by sys.report, which nothing an agent writes can reach.
function __loop(what, scope, paths) -- paths as JSON
  local function report(t) sys.report(json.encode(t)) end
  local ok, why = xpcall(function() require("loop")[what](scope, json.decode(paths), report) end, tostring)
  if not ok then sys.ewrite("lua: " .. why .. "\n") return 1 end
  return 0
end

function __serve(req)
  if req.page then return page(req) end
  return 404, {}, "This computer has no page here: ui/index.lui is its first."
end

-- ports.sqlite, the database port on a LuaJIT host: LuaJIT's FFI over the system SQLite.
-- This is host code, not the harness: Tablua itself never touches the FFI, and
-- any host that can run SQL (its own database binding) can stand in.
--
--   local db = require("ports.sqlite").open(":memory:")
--   db:exec(sql, params) -> rows, each { column = value } (nil for NULL)
--
-- exec runs every statement in `sql`; `params` bind to the last one and are
-- a list of strings, numbers, booleans or false-as-NULL. Errors raise with
-- SQLite's message. AROCK_SQLITE names the library to load.
local ffi = require("ffi")

ffi.cdef([[
typedef struct sqlite3 sqlite3;
typedef struct sqlite3_stmt sqlite3_stmt;
int sqlite3_open(const char *filename, sqlite3 **db);
int sqlite3_busy_timeout(sqlite3 *db, int ms);
int sqlite3_close_v2(sqlite3 *db);
const char *sqlite3_errmsg(sqlite3 *db);
int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int n, sqlite3_stmt **stmt, const char **tail);
int sqlite3_step(sqlite3_stmt *stmt);
int sqlite3_finalize(sqlite3_stmt *stmt);
int sqlite3_bind_parameter_count(sqlite3_stmt *stmt);
int sqlite3_bind_text(sqlite3_stmt *stmt, int i, const char *s, int n, void (*destructor)(void *));
int sqlite3_bind_int64(sqlite3_stmt *stmt, int i, int64_t v);
int sqlite3_bind_double(sqlite3_stmt *stmt, int i, double v);
int sqlite3_bind_null(sqlite3_stmt *stmt, int i);
int sqlite3_column_count(sqlite3_stmt *stmt);
const char *sqlite3_column_name(sqlite3_stmt *stmt, int i);
int sqlite3_column_type(sqlite3_stmt *stmt, int i);
int64_t sqlite3_column_int64(sqlite3_stmt *stmt, int i);
double sqlite3_column_double(sqlite3_stmt *stmt, int i);
const unsigned char *sqlite3_column_text(sqlite3_stmt *stmt, int i);
int sqlite3_column_bytes(sqlite3_stmt *stmt, int i);
]])

local ROW, DONE = 100, 101
local INTEGER, FLOAT, NULL = 1, 2, 5
local TRANSIENT = ffi.cast("void (*)(void *)", -1)

local function load()
  local names = { os.getenv("AROCK_SQLITE"), "/opt/homebrew/opt/sqlite/lib/libsqlite3.dylib", "sqlite3" }
  for i = 1, 3 do
    local ok, lib = pcall(ffi.load, names[i])
    if names[i] and ok then return lib end
  end
  error("no SQLite library found; set AROCK_SQLITE")
end

local C = load()
local M = {}
M.BUSY_MS = 5000
local DB = {}
DB.__index = DB

function M.open(path)
  local handle = ffi.new("sqlite3*[1]")
  if C.sqlite3_open(path, handle) ~= 0 then
    error("cannot open " .. path .. ": " .. ffi.string(C.sqlite3_errmsg(handle[0])))
  end
  -- another connection's write (the app's trace while the desk runner reads it) is waited for, not failed on
  C.sqlite3_busy_timeout(handle[0], M.BUSY_MS)
  return setmetatable({ h = handle[0] }, DB)
end

function DB:fail()
  error(ffi.string(C.sqlite3_errmsg(self.h)), 0)
end

local function bind(self, stmt, params)
  for i = 1, C.sqlite3_bind_parameter_count(stmt) do
    local v, rc = params[i], 0
    if type(v) == "number" and v == math.floor(v) and math.abs(v) < 2 ^ 53 then
      rc = C.sqlite3_bind_int64(stmt, i, v)
    elseif type(v) == "number" then
      rc = C.sqlite3_bind_double(stmt, i, v)
    elseif v == nil or v == false then
      rc = C.sqlite3_bind_null(stmt, i)
    else
      v = tostring(v)
      rc = C.sqlite3_bind_text(stmt, i, v, #v, TRANSIENT)
    end
    if rc ~= 0 then self:fail() end
  end
end

local function column(stmt, i)
  local t = C.sqlite3_column_type(stmt, i)
  if t == INTEGER then return tonumber(C.sqlite3_column_int64(stmt, i)) end
  if t == FLOAT then return C.sqlite3_column_double(stmt, i) end
  if t == NULL then return nil end
  return ffi.string(C.sqlite3_column_text(stmt, i), C.sqlite3_column_bytes(stmt, i))
end

function DB:exec(sql, params)
  local stmt, tail = ffi.new("sqlite3_stmt*[1]"), ffi.new("const char*[1]")
  local rest, rows = sql, {}
  while rest and rest:find("%S") do
    if C.sqlite3_prepare_v2(self.h, rest, #rest, stmt, tail) ~= 0 then self:fail() end
    local s = stmt[0]
    rest = tail[0] ~= nil and ffi.string(tail[0]) or nil
    if s ~= nil then
      rows = {}
      local last = not (rest and rest:find("%S"))
      if last and params then bind(self, s, params) end
      local names, n = {}, C.sqlite3_column_count(s)
      for i = 0, n - 1 do names[i] = ffi.string(C.sqlite3_column_name(s, i)) end
      local rc = C.sqlite3_step(s)
      while rc == ROW do
        local row = {}
        for i = 0, n - 1 do row[names[i]] = column(s, i) end
        rows[#rows + 1] = row
        rc = C.sqlite3_step(s)
      end
      C.sqlite3_finalize(s)
      if rc ~= DONE then self:fail() end
    end
  end
  return rows
end

function DB:close()
  C.sqlite3_close_v2(self.h)
end

return M

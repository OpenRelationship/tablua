-- The fetch port on the test host: LuaJIT's FFI over the system libcurl.
-- Host code, not core: the ports never load it, and a browser or phone host
-- brings its own fetch. The key travels only in the request's header, never
-- on a command line.
--
--   local fetch = require("ports.curl").fetch
--   fetch{ method = "POST"|"PUT"|"GET", url, headers = { k = v }, body, timeout = seconds, on_data } -> { status, body }
--
-- on_data(chunk), when given, hears the body a chunk at a time as it arrives (a streamed reply); the whole body is
-- still returned. An error it raises is dropped, so the transfer is never cut by its listener.
--
-- A transport failure (DNS, TLS, timeout) raises with curl's message.
--
-- Requests from one Lua state share a connection cache, DNS answers and TLS sessions (a curl share handle), so a
-- second call to the same host reuses the connection instead of paying for a new one (features/computer-speed).
-- A Lua state is one thread, so the share needs no locks; each state that loads this has its own.
local ffi = require("ffi")

ffi.cdef([[
typedef void CURL;
struct curl_slist;
CURL *curl_easy_init(void);
int curl_easy_setopt(CURL *curl, int option, ...);
int curl_easy_perform(CURL *curl);
int curl_easy_getinfo(CURL *curl, int info, ...);
void curl_easy_cleanup(CURL *curl);
const char *curl_easy_strerror(int code);
struct curl_slist *curl_slist_append(struct curl_slist *list, const char *s);
void curl_slist_free_all(struct curl_slist *list);
typedef void CURLSH;
CURLSH *curl_share_init(void);
int curl_share_setopt(CURLSH *share, int option, ...);
]])

local C = ffi.load(os.getenv("TABLUA_CURL") or "libcurl.4.dylib")

local URL, POSTFIELDS, HTTPHEADER, CUSTOMREQUEST = 10002, 10015, 10023, 10036
local WRITEFUNCTION, POSTFIELDSIZE, TIMEOUT_MS, NOSIGNAL = 20011, 60, 155, 99
local RESPONSE_CODE = 0x200002
local SHARE, SHOPT_SHARE = 10100, 1
local LOCK_DNS, LOCK_SSL_SESSION, LOCK_CONNECT = 3, 4, 5

local share = C.curl_share_init()
if share ~= nil then
  for _, d in ipairs({ LOCK_DNS, LOCK_SSL_SESSION, LOCK_CONNECT }) do
    C.curl_share_setopt(share, SHOPT_SHARE, ffi.cast("int", d))
  end
end

local M = {}

function M.fetch(req)
  local curl = assert(C.curl_easy_init(), "curl_easy_init failed")
  local chunks = {}
  local write = ffi.cast("size_t (*)(char *, size_t, size_t, void *)", function(p, size, n)
    local s = ffi.string(p, size * n)
    chunks[#chunks + 1] = s
    if req.on_data then pcall(req.on_data, s) end
    return size * n
  end)
  local headers = nil
  local typed = false
  for k, v in pairs(req.headers or {}) do
    headers = C.curl_slist_append(headers, k .. ": " .. v)
    typed = typed or k:lower() == "content-type"
  end
  -- A body makes curl add a form Content-Type; a signed-URL PUT must carry
  -- only the headers it was signed with, so drop it unless one was given.
  if req.body and not typed then headers = C.curl_slist_append(headers, "Content-Type:") end
  local body = req.body or ""
  C.curl_easy_setopt(curl, URL, req.url)
  C.curl_easy_setopt(curl, CUSTOMREQUEST, req.method or "GET")
  C.curl_easy_setopt(curl, HTTPHEADER, headers)
  C.curl_easy_setopt(curl, WRITEFUNCTION, write)
  C.curl_easy_setopt(curl, NOSIGNAL, ffi.cast("long", 1))
  if share ~= nil then C.curl_easy_setopt(curl, SHARE, share) end
  C.curl_easy_setopt(curl, TIMEOUT_MS, ffi.cast("long", (req.timeout or 30) * 1000))
  if req.body and req.method ~= "GET" then
    C.curl_easy_setopt(curl, POSTFIELDSIZE, ffi.cast("long", #body))
    C.curl_easy_setopt(curl, POSTFIELDS, body)
  end
  local rc = C.curl_easy_perform(curl)
  local code = ffi.new("long[1]")
  C.curl_easy_getinfo(curl, RESPONSE_CODE, code)
  C.curl_easy_cleanup(curl)
  C.curl_slist_free_all(headers)
  write:free()
  if rc ~= 0 then error("curl: " .. ffi.string(C.curl_easy_strerror(rc)), 0) end
  return { status = tonumber(code[0]), body = table.concat(chunks) }
end

-- Seconds since an arbitrary start, for timing calls.
ffi.cdef([[ int gettimeofday(struct timeval_ { long s; int us; } *tv, void *tz); ]])
function M.now()
  local tv = ffi.new("struct timeval_")
  ffi.C.gettimeofday(tv, nil)
  return tonumber(tv.s) + tonumber(tv.us) / 1e6
end

return M

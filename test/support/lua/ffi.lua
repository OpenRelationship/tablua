-- store.ffi on the test host: Arock Core's unit tests open databases with
-- require("store.ffi").open(path); here that is an Exqlite connection behind
-- the same db:exec(sql, params) port the runs use.
-- A connection waits BUSY_MS for another's write lock, as store.ffi's does.
local BUSY_MS = 5000

return {
  BUSY_MS = BUSY_MS,
  open = function(path)
    local h = __test.db_open(path)
    __test.db_exec(h, "pragma busy_timeout = " .. BUSY_MS)
    return { exec = function(_, sql, params) return __test.db_exec(h, sql, params) end }
  end,
}

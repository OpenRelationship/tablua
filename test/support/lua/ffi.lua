-- store.ffi on the test host: Volvox's unit tests open databases with
-- require("store.ffi").open(path); here that is an Exqlite connection behind
-- the same db:exec(sql, params) port the runs use.
return {
  open = function(path)
    local h = __test.db_open(path)
    return { exec = function(_, sql, params) return __test.db_exec(h, sql, params) end }
  end,
}

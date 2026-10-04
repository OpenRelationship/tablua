-- Content kept once, by id. The id is the host's digest when it gives one
-- (alog.open's opts.hash, e.g. SHA-256 from the host's crypto) or else a
-- portable 64-bit hash of every byte with the length. Either way a blob is
-- compared byte for byte before it is reused, so two contents that share an
-- id are both kept (the second as id.2, and so on) and none is ever lost.
local M = {}

-- Arithmetic only, every step below 2^53, so LuaJIT, Lua 5.4 and tv-labs
-- lua give the same id. It suits LuaJIT and small contents; in tv-labs lua it
-- costs about 10 ms at 16 KB and grows faster than the content, so a host
-- there passes its native digest (Moss: SHA-256 from :crypto, 0.6 ms at 64 KB).
function M.hash(s)
  local a, b = 0, 0
  for i = 1, #s do
    local c = s:byte(i)
    a = (a * 31 + c) % 4294967291
    b = (b * 131 + c) % 4294967279
  end
  return ("%08x%08x-%d"):format(a, b, #s)
end

-- Text recall indexes: no NUL byte (that is binary), and at most RECALL bytes.
M.RECALL = 65536

function M.text(s)
  if s:find("\0", 1, true) then return nil end
  return #s > M.RECALL and s:sub(1, M.RECALL) or s
end

-- Keeps content and gives back its id; inside the caller's transaction.
function M.put(db, hash, content)
  local base = hash(content)
  local id, n = base, 1
  while true do
    local r = db:exec("select content = ? as same from blobs where id = ?", { content, id })[1]
    if not r then
      db:exec("insert into blobs (id, content) values (?, ?)", { id, content })
      return id
    end
    if r.same == 1 then return id end
    n = n + 1
    id = base .. "." .. n
  end
end

function M.get(db, id)
  local r = db:exec("select content from blobs where id = ?", { id })[1]
  return r and r.content
end

return M

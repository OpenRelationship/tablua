-- date: times as seconds since 1970 (UTC), read and written as ISO 8601, with calendar arithmetic. Pure Lua, so it
-- answers the same on every computer whatever its clock's zone.
--
--   date.now()                        -> seconds
--   date.parse("2026-10-01")          -> seconds; also "2026-10-01T09:30:00Z" and "2026-10-01 09:30"
--   date.iso(t)                       -> "2026-10-01T09:30:00Z";  date.day(t) -> "2026-10-01"
--   date.parts(t)                     -> { year, month, day, hour, min, sec, weekday (1 Monday ... 7 Sunday) }
--   date.add(t, { days = 3, months = 1, hours = 2 })
--   date.diff(a, b, "days")           -> a minus b, whole days: days left until an event is date.diff(event, today, "days")
--   date.format(t, "%Y-%m-%d %H:%M")  (%Y %m %d %H %M %S %a %A %b %B %j)
local date = {}

local DAY = 86400
local NAMES = { "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday" }
local MONTHS = { "January", "February", "March", "April", "May", "June", "July", "August", "September", "October",
  "November", "December" }

-- days since 1970-01-01 for a civil date, and back (Howard Hinnant's algorithms)
local function days_from(y, m, d)
  y = m <= 2 and y - 1 or y
  local era = math.floor(y / 400)
  local yoe = y - era * 400
  local doy = math.floor((153 * (m + (m > 2 and -3 or 9)) + 2) / 5) + d - 1
  local doe = yoe * 365 + math.floor(yoe / 4) - math.floor(yoe / 100) + doy
  return era * 146097 + doe - 719468
end

local function civil(z)
  z = z + 719468
  local era = math.floor(z / 146097)
  local doe = z - era * 146097
  local yoe = math.floor((doe - math.floor(doe / 1460) + math.floor(doe / 36524) - math.floor(doe / 146096)) / 365)
  local y = yoe + era * 400
  local doy = doe - (365 * yoe + math.floor(yoe / 4) - math.floor(yoe / 100))
  local mp = math.floor((5 * doy + 2) / 153)
  local d = doy - math.floor((153 * mp + 2) / 5) + 1
  local m = mp < 10 and mp + 3 or mp - 9
  return m <= 2 and y + 1 or y, m, d
end

function date.now() return math.floor(os.time()) end

function date.time(y, m, d, h, mi, s)
  return days_from(y, m, d) * DAY + (h or 0) * 3600 + (mi or 0) * 60 + (s or 0)
end

function date.parse(s)
  local y, m, d, rest = string.match(tostring(s), "^(%d%d%d%d)%-(%d%d)%-(%d%d)(.*)$")
  if not y then return nil, "not a date: " .. tostring(s) end
  local h, mi, sec = string.match(rest, "^[T ](%d%d):(%d%d):?(%d*)")
  local t = date.time(tonumber(y), tonumber(m), tonumber(d), tonumber(h) or 0, tonumber(mi) or 0, tonumber(sec) or 0)
  local sign, oh, om = string.match(rest, "([%+%-])(%d%d):?(%d%d)$")
  if sign then t = t - (sign == "+" and 1 or -1) * (tonumber(oh) * 3600 + tonumber(om) * 60) end
  return t
end

function date.parts(t)
  t = math.floor(t)
  local days = math.floor(t / DAY)
  local secs = t - days * DAY
  local y, m, d = civil(days)
  return {
    year = y, month = m, day = d,
    hour = math.floor(secs / 3600), min = math.floor(secs % 3600 / 60), sec = secs % 60,
    weekday = (days + 3) % 7 + 1, yday = days - days_from(y, 1, 1) + 1,
  }
end

local function two(n) return string.format("%02d", n) end

function date.format(t, fmt)
  local p = date.parts(t)
  local map = {
    Y = tostring(p.year), m = two(p.month), d = two(p.day), H = two(p.hour), M = two(p.min), S = two(p.sec),
    A = NAMES[p.weekday], a = string.sub(NAMES[p.weekday], 1, 3), B = MONTHS[p.month],
    b = string.sub(MONTHS[p.month], 1, 3), j = string.format("%03d", p.yday), ["%"] = "%",
  }
  return (string.gsub(fmt, "%%(.)", function(c) return map[c] or ("%" .. c) end))
end

function date.iso(t) return date.format(t, "%Y-%m-%dT%H:%M:%SZ") end
function date.day(t) return date.format(t, "%Y-%m-%d") end

function date.add(t, by)
  local p = date.parts(t)
  local months = (by.years or 0) * 12 + (by.months or 0)
  if months ~= 0 then
    local total = p.year * 12 + (p.month - 1) + months
    local y, m = math.floor(total / 12), total % 12 + 1
    local _, _, lastday = civil(days_from(m == 12 and y + 1 or y, m == 12 and 1 or m + 1, 1) - 1)
    t = date.time(y, m, math.min(p.day, lastday), p.hour, p.min, p.sec)
  end
  return t + (by.weeks or 0) * 7 * DAY + (by.days or 0) * DAY + (by.hours or 0) * 3600 + (by.minutes or 0) * 60 +
    (by.seconds or 0)
end

function date.diff(a, b, unit)
  local s = a - b
  local per = ({ days = DAY, hours = 3600, minutes = 60, seconds = 1, weeks = 7 * DAY })[unit or "seconds"]
  return math.floor(s / per)
end

return date

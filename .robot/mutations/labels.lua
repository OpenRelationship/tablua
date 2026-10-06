-- The step labels (tablua-local: tl/labels.py offline, bench/terminal/labels.lua live), each rule broken once in each
-- copy: their tests must fail for every one.
return {
  dir = "../tablua-local",
  cmd = "python3 -m unittest tl.labels_test && cd bench/terminal && luajit labels_test.lua",
  { "tl/labels.py", "                if test in reached:", "                if True:", "py: a test's first reach counted" },
  { "tl/labels.py", "                if test in reached:\n                    further = True",
    "                if test in reached:\n                    pass", "py: reaching further ignored" },
  { "tl/labels.py", "        safe = not (best is not None and top is not None and top < best)", "        safe = True",
    "py: fewer passing not unsafe" },
  { "tl/labels.py", "        safe = safe and not any(a[1] in failed_keys and a[2] not in (None, 0) for a in mine)", "",
    "py: a failure repeated not unsafe" },
  { "tl/labels.py", "any(a[1] not in typed and a[2] == 0 for a in mine)", "any(a[2] == 0 for a in mine)",
    "py: a repeat counted as new" },
  { "bench/terminal/labels.lua", "        if reached[test] ~= nil then further = true end", "        further = true",
    "lua: a test's first reach counted" },
  { "bench/terminal/labels.lua", "  local safe = not (best ~= nil and top ~= nil and top < best)", "  local safe = true",
    "lua: fewer passing not unsafe" },
  { "bench/terminal/labels.lua", "      if failed_keys[a.keys] and a.exit ~= nil and a.exit ~= 0 then safe = false end", "",
    "lua: a failure repeated not unsafe" },
  { "bench/terminal/labels.lua", "        if not typed[a.keys] and a.exit == 0 then further = true end",
    "        if a.exit == 0 then further = true end", "lua: a repeat counted as new" },
}

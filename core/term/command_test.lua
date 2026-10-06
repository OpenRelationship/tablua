-- Command lines as columns: their programs, the files they write, and whether they only look.
local spec = require("spec")
local command = require("term.command")

local function p(line) return command.parse(line) end

spec.test("each command's program, after what goes in front of it, in order", function()
  local r = p("cd /app && DEBIAN_FRONTEND=noninteractive sudo apt-get install -y gcc | tail -3; timeout 60 ./run.sh")
  spec.same(r.programs, { "cd", "apt-get", "tail", "run.sh" })
  spec.same({ r.program, r.pipes, r.chained, r.reads }, { "apt-get", 1, 2, false })
end)

spec.test("only reads: every program looks and nothing is written", function()
  spec.ok(command.only_reads("cat /app/main.tex"), "cat")
  spec.ok(command.only_reads("cd /app && grep -n mind synonyms.txt | head"), "grep and head")
  spec.ok(command.only_reads("sed -n 1,20p a.tex"), "sed -n")
  spec.ok(command.only_reads("grep x f >/dev/null 2>&1"), "to /dev/null")
  spec.ok(command.only_reads("git status && git diff"), "git status")
  spec.ok(not command.only_reads("cat a > b"), "a redirect writes")
  spec.ok(not command.only_reads("sed -i s/a/b/ f"), "sed -i")
  spec.ok(not command.only_reads("pdflatex main.tex 2>&1 | grep warn"), "pdflatex")
  spec.ok(not command.only_reads("ls | tee out.txt"), "tee writes")
end)

spec.test("the files it writes: redirections and tee, not /dev/null or a descriptor", function()
  spec.same(p("make 2>&1 | tee /tmp/build.log; echo done >> notes.txt; ls > /dev/null").writes,
    { "/tmp/build.log", "notes.txt" })
end)

spec.test("quotes and heredoc bodies are kept whole; a comment is no command", function()
  local r = p("python3 -c 'import a; print(1 | 2)' && echo \"x && y\"")
  spec.same(r.programs, { "python3", "echo" })
  r = p("cat > /app/t.py << 'EOF'\nimport os; os.system('rm -rf x && ls')\nEOF\npython3 /app/t.py")
  spec.same({ r.programs[1], r.programs[2], r.writes[1], r.heredoc }, { "cat", "python3", "/app/t.py", true })
  r = p("# Let me look at the log first\ncat main.log")
  spec.same({ r.programs, r.comments, r.reads }, { { "cat" }, 1, true })
end)

spec.test("the program is the first that is not cd or export; the shell's own words are no program", function()
  spec.eq(p("cd /app && make -j4").program, "make")
  spec.eq(p("cd /app").program, "cd")
  local r = p("cd /app; if [ -f a ]; then cat a; else echo none; fi")
  spec.same({ r.program, r.programs }, { "[", { "cd", "[", "cat", "echo" } })
end)

spec.test("a background job, and nothing typed", function()
  spec.same({ p("nohup python3 server.py > /tmp/s.log 2>&1 &").background, p("").program }, { 1, "" })
end)

spec.run()

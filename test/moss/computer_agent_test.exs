defmodule Moss.ComputerAgentTest do
  # The computer's own agent (Moss.Computer.Agent over core/agent), with Jev and Mercury answered by
  # Req.Test in their places: Jev decides every step, from the moves the stage allows, before Mercury is asked;
  # Mercury fills the move Jev chose; the person's part is waited for, never done; every decision is a Decide row
  # joined to its step's Outcome by address; and the run counts each mind's calls.
  use ExUnit.Case, async: false

  alias Moss.{Computer, Log}

  setup do
    old = for k <- ~w(OPENROUTER_API_KEY INCEPTION_API_KEY PRIORLABS_API_KEY), into: %{}, do: {k, System.get_env(k)}
    System.put_env("OPENROUTER_API_KEY", "jev-key")
    System.put_env("INCEPTION_API_KEY", "mercury-key")
    System.delete_env("PRIORLABS_API_KEY")

    on_exit(fn ->
      for {k, v} <- old, do: if(v, do: System.put_env(k, v), else: System.delete_env(k))
    end)

    calls = start_supervised!({Agent, fn -> [] end})
    Req.Test.stub(Moss.Fetch, &answer(&1, calls))
    %{calls: calls, id: "agent-#{System.unique_integer([:positive])}"}
  end

  # Jev picks a wait when the stage offers one, else the feature; Mercury writes the feature with one call
  defp answer(conn, calls) do
    {:ok, body, conn} = Plug.Conn.read_body(conn)
    sent = Jason.decode!(body)

    case conn.request_path do
      "/api/alpha/decisions" ->
        options = Map.keys(sent["questions"]["next"]["criteria"])
        choice = Enum.find(["wait_for_agreement", "write_feature"], &(&1 in options))
        Agent.update(calls, &(&1 ++ [{:jev, options, choice}]))
        probabilities = Map.new(options, &{&1, if(&1 == choice, do: 0.9, else: 0.1 / (length(options) - 1))})

        Req.Test.json(conn, %{
          "model" => "typesafe/jev-1.13",
          "answers" => %{"next" => %{"choice" => choice, "probabilities" => probabilities, "confidence" => 0.85}}
        })

      "/v1/chat/completions" ->
        Agent.update(calls, &(&1 ++ [{:mercury, sent}]))
        call = %{"cmd" => "new feature hello"}

        Req.Test.json(conn, %{
          "model" => "mercury-2.5",
          "usage" => %{"prompt_tokens" => 1000, "completion_tokens" => 100},
          "choices" => [
            %{"message" => %{"tool_calls" => [%{"id" => "c1", "type" => "function",
              "function" => %{"name" => "computer", "arguments" => Jason.encode!(call)}}]}}
          ]
        })
    end
  end

  test "the writer reads only of pages in org and Lua (arock issue #2)", %{calls: calls, id: id} do
    Moss.Computer.Agent.run(id, "Make me a hello page.", at: "org:rock/mail/1")
    [{:mercury, fill} | _] = for {:mercury, _} = m <- Agent.get(calls, & &1), do: m
    [system, _turn] = fill["messages"]
    assert system["content"] =~ "ui/index.org (served at /"
    assert system["content"] =~ "new page index"
    refute system["content"] =~ ".lui"
  end

  test "Jev decides every step before Mercury fills it, and the person's agreement is waited for", %{calls: calls, id: id} do
    run = Moss.Computer.Agent.run(id, "Make me a hello page.", at: "org:rock/mail/1")

    assert run.outcome == "waiting"
    assert run.why == "waiting for the person's agreement to the feature"
    log = Agent.get(calls, & &1)

    # first Jev, offered only what a computer with no feature allows; then Mercury, told Jev's move
    assert [{:jev, first, "write_feature"}, {:mercury, fill} | waits] = log
    assert Enum.sort(first) == ["read_help", "think", "write_feature"]
    [system, turn] = fill["messages"]
    assert system["role"] == "system" and system["content"] =~ "<critical_rules>"
    assert String.ends_with?(String.trim(system["content"]), "</critical_rules>")
    assert turn["content"] =~ "<next_move>\nwrite_feature: "
    assert fill["tool_choice"] == "required" and fill["temperature"] == 0.6
    assert [%{"function" => %{"strict" => true}}] = fill["tools"]

    # the feature written and not agreed: only waiting, or changing it, is offered; Mercury is not asked to wait
    assert [{:jev, offered, "wait_for_agreement"} | _] = waits
    assert Enum.sort(offered) == ["think", "wait_for_agreement", "write_feature"]
    assert Enum.all?(waits, &match?({:jev, _, "wait_for_agreement"}, &1))

    # every mind's calls counted; every decision joined to its outcome by the step's address
    assert run.counts["jev"] == length(log) - 1 and run.counts["mercury"] == 1
    assert run.counts["mercury_cost"] > 0
    state = :sys.get_state(Computer.whereis(id))
    rows = Log.rows(state.disk.conn, ["Decide", "Outcome"])
    decided = for %{"keyword" => "Decide", "args" => [at | _]} <- rows, do: at
    outcomes = for %{"keyword" => "Outcome", "args" => [at | _]} <- rows, String.contains?(at, "/step/"), do: at
    assert decided == ["org:rock/mail/1/step/1", "org:rock/mail/1/step/2", "org:rock/mail/1/step/3", "org:rock/mail/1/step/4"]
    assert outcomes == decided

    # the step's own commands are logged under its address, so the log reads a step's work as one
    commands = Log.rows(state.disk.conn, ["Run Command"])
    assert [%{"args" => ["cd '/home' && new feature hello" | _]}] =
             Enum.filter(commands, &(&1["task"] == "org:rock/mail/1/step/1"))
  end

  test "the person's agreement moves the stage on, and Jev is offered the building moves", %{calls: calls, id: id} do
    agree = fn id ->
      st = :sys.get_state(Computer.whereis(id))
      for %{stage: "written", path: p} <- Moss.Computer.Board.board(st), do: Computer.agree(id, p)
    end

    Moss.Computer.Agent.run(id, "Make me a hello page.", between: agree, max_steps: 2)
    [_, _, {:jev, offered, _}] = Agent.get(calls, & &1)
    assert "write_steps" in offered and "run_test" in offered
    refute "publish" in offered

    # and every step is a typed row in the computer's own file (core/tablua, world/record.lua)
    sql = fn q -> {:ok, rows} = Computer.agent(id, :sql, [q, []]); rows end
    decides = length(Moss.Log.rows(:sys.get_state(Computer.whereis(id)).disk.conn, ["Decide"]))
    assert decides >= 1
    assert [%{"n" => ^decides}] = sql.("select count(*) as n from tablua_decision")
    assert [%{"chosen" => "write_feature", "by" => "jev"} | _] = sql.("select chosen, by from tablua_decision order by n")
    assert [%{"stage" => "no_feature"} | _] = sql.("select stage from tablua_state order by n")
    assert [%{"n" => n}] = sql.("select count(*) as n from tablua_candidate")
    assert n >= 2
    assert [%{"n" => outcomes}] = sql.("select count(*) as n from tablua_outcome")
    assert outcomes in [decides - 1, decides]
  end

  # the same failure through two fixes: fix_failure is taken off the table until Jev has the agent think it through
  test "a fix that leaves the same failure did nothing, twice running it waits on thinking, and then it escalates", %{calls: calls, id: id} do
    Computer.run(id, "help")
    disk = :sys.get_state(Computer.wake!(id)).disk
    :ok = Moss.Computer.Disk.write(disk, "/home/features/hello.feature",
      "Feature: Hello\n  Scenario: Hi\n    Given the page says hello\n")
    :ok = Moss.Computer.Disk.write(disk, "/home/code/steps/hello.lua",
      ~s|test.step("the page says hello", function(w) test.ok(false, "no hello") end)\n|)
    :ok = Computer.agree(id, "/home/features/hello.feature")
    Computer.run(id, "test")

    Req.Test.stub(Moss.Fetch, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      sent = Jason.decode!(body)

      case conn.request_path do
        "/api/alpha/decisions" ->
          options = Map.keys(sent["questions"]["next"]["criteria"])
          choice = Enum.find(["fix_failure", "think", "rewrite"], &(&1 in options))
          Agent.update(calls, &(&1 ++ [{:jev, options, choice}]))
          probabilities = Map.new(options, &{&1, if(&1 == choice, do: 0.9, else: 0.1 / (length(options) - 1))})
          # the cause, asked beside the move while something fails: the steps
          cause = if sent["questions"]["cause"], do: %{"cause" => %{"choice" => "the_steps", "probabilities" => %{"the_steps" => 0.8}}}, else: %{}
          # Jev's fan-out features (world/features.lua): the ask's kind once, and how done the app is; ask_edit
          # left unanswered, as an optional question may be
          feats =
            %{"ask_dates" => %{"noul" => 0.1}, "done" => %{"score" => "a little of it works",
              "probabilities" => %{"a little of it works" => 1.0}}}
            |> Map.filter(fn {k, _} -> sent["questions"][k] end)
          answers = cause |> Map.merge(feats) |> Map.put("next", %{"choice" => choice, "probabilities" => probabilities})
          Req.Test.json(conn, %{"answers" => answers})

        "/v1/chat/completions" ->
          message =
            if sent["tools"],
              do: %{"tool_calls" => [%{"id" => "c", "type" => "function",
                "function" => %{"name" => "computer", "arguments" => ~s({"cmd": "status"})}}]},
              else: %{"content" => "The step checks nothing real; write the app's code first."}

          Req.Test.json(conn, %{"usage" => %{}, "choices" => [%{"message" => message}]})
      end
    end)

    Moss.Computer.Agent.run(id, "Make me a hello page.", max_steps: 7)
    jev = for {:jev, offered, choice} <- Agent.get(calls, & &1), do: {"fix_failure" in offered, choice}

    # one fix after thinking, which does not wipe the count; through the dead end neither is offered, and the
    # agent rewrites
    assert jev == [{true, "fix_failure"}, {true, "fix_failure"}, {false, "think"}, {true, "fix_failure"},
                   {false, "think"}, {true, "fix_failure"}, {false, "rewrite"}]

    # and straight after thinking, thinking again is not offered
    [{:jev, first, _}, _, {:jev, third, _}, {:jev, fourth, _} | rest] = Agent.get(calls, & &1)
    {:jev, seventh, _} = List.last(rest)
    refute "think" in seventh
    assert "think" in third and "think" not in fourth

    # and the agreed feature is offered for changing only once fixing has stopped helping
    assert "write_feature" not in first and "write_feature" in third

    # each fix's note says it left the same failure, and its outcome is that it did nothing
    rows = Log.rows(:sys.get_state(Computer.whereis(id)).disk.conn, ["Outcome"])
    steps = for %{"args" => [at, outcome, note | _]} <- rows, String.contains?(at, "/step/"), do: {outcome, note}
    assert [{"no_effect", n1}, {"no_effect", n2}, {"complete", _}, {"no_effect", _} | _] = steps
    assert n1 =~ "] Cause placed in the_steps. Test after: 0 of 1 pass (before: 0 of 1). The same failure as before this step (1 changes"
    assert n2 =~ "(2 changes running have left it): Hi: Given the page says hello: /home/code/steps/hello.lua:1: no hello"

    # Jev's fan-out answers are feature rows of each step: the ask's kind asked once and kept, done as a 0-1 mean
    sql = fn q -> {:ok, rows} = Computer.agent(id, :sql, [q, []]); rows end
    assert [%{"n" => 7}] = sql.("select count(*) as n from tablua_feature where name = 'ask_dates'")
    assert [%{"value" => v} | _] = sql.("select value from tablua_feature where name = 'done' order by n")
    assert_in_delta v, 1 / 3, 0.001
    assert [%{"n" => 0}] = sql.("select count(*) as n from tablua_feature where name = 'ask_edit'")

    # the harness's gates as rows, written once when the run starts
    assert [%{"n" => 10}] = sql.("select count(*) as n from tablua_gate where retired_by is null")

    # the harness's behaviour model: every step has its effects, from the facts before and after it
    assert [%{"n" => 7}] = sql.("select count(distinct n) as n from tablua_effect")
    assert [%{"n" => same}] = sql.("select count(*) as n from tablua_effect where keyword = 'Same Line Failing'")
    assert same >= 1
    asked = for {:jev, _, _} <- Agent.get(calls, & &1), do: 1
    assert length(asked) == 7
  end

  # Jev's none-of-these: twice running, the run ends blocked, with what is missing in Mercury's words
  test "Jev can say no move can make progress, and twice running that ends the run blocked", %{id: id} do
    Req.Test.stub(Moss.Fetch, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      sent = Jason.decode!(body)

      case conn.request_path do
        "/api/alpha/decisions" ->
          options = Map.keys(sent["questions"]["next"]["criteria"])
          choice = if "blocked" in options, do: "blocked", else: "write_feature"
          Req.Test.json(conn, %{"answers" => %{"next" => %{"choice" => choice, "probabilities" => %{choice => 0.9}}}})

        "/v1/chat/completions" ->
          unless sent["tools"], do: assert(sent["messages"] |> hd() |> Map.get("content") =~ "none of its moves can make progress")
          Req.Test.json(conn, %{"usage" => %{}, "choices" => [%{"message" => %{"content" => "The filler answers 400 every time."}}]})
      end
    end)

    run = Moss.Computer.Agent.run(id, "Make me a hello page.")
    # stopping is offered only once something is wrong: here a move Mercury made no call for
    assert %{outcome: "blocked", why: "blocked: The filler answers 400 every time.", steps: 3} = run
    rows = Log.rows(:sys.get_state(Computer.whereis(id)).disk.conn, ["Outcome"])
    assert [{"no_effect", _}, {"blocked", "Blocked: The filler" <> _}, {"blocked", _}] =
             for(%{"args" => [at, o, note | _]} <- rows, String.contains?(at, "/step/"), do: {o, note})
  end

  # a page that does not answer says why in the facts both minds read, not its status alone
  test "a page that does not answer carries its error in the facts", %{id: id} do
    Computer.run(id, "help")
    disk = :sys.get_state(Computer.wake!(id)).disk
    :ok = Moss.Computer.Disk.write(disk, "/home/ui/index.lui", "<lua>\n  local d = nil\n</lua>\n<p>{{ d.name }}</p>\n")
    assert [%{"path" => "/", "status" => 500, "error" => error}] = Computer.agent(id, :facts, ["org:x"])["pages"]
    assert error =~ "index.lui"

    # and one that answers names each {{ e }} that showed nothing, for the agent alone
    :ok = Moss.Computer.Disk.write(disk, "/home/ui/index.lui", "<lua>\n  local d = { days = 5 }\n</lua>\n<p>{{ d.days_left }}</p>\n")
    assert [%{"status" => 200, "nils" => "ui/index.lui:4: {{ d.days_left }}"}] = Computer.agent(id, :facts, ["org:x"])["pages"]
    assert {200, headers, _, _} = Computer.serve(id, %{"method" => "GET", "path" => "/"})
    refute Map.has_key?(headers, "x-moss-nil")

    # a feature with no scenarios is failing, whatever else passes
    :ok = Moss.Computer.Disk.write(disk, "/home/features/empty.feature", "Feature: nothing yet\n")
    :ok = Computer.agree(id, "/home/features/empty.feature")
    Computer.run(id, "test")
    assert [failing] = Computer.agent(id, :facts, ["org:x"])["tests"]["failing"]
    assert failing =~ "features/empty.feature has no scenarios"
    Computer.run(id, "rm features/empty.feature")

    # and one that opens its database itself is named: no step tests what it shows
    :ok = Moss.Computer.Disk.write(disk, "/home/ui/index.lui", "<lua>\n  local d = db.open(\"data/x.dbl\")\n</lua>\n<p>x</p>\n")
    assert [%{"own_db" => "ui/index.lui"}] = Computer.agent(id, :facts, ["org:x"])["pages"]
  end

  # a change that breaks scenarios that passed can be put back: Jev is offered undo, and the files return as they were
  test "a change that breaks what passed is offered undo, and undo puts its files back", %{calls: calls, id: id} do
    good = ~s|test.step("the page says hello", function(w) test.ok(true) end)\n|
    Computer.run(id, "help")
    disk = :sys.get_state(Computer.wake!(id)).disk
    :ok = Moss.Computer.Disk.write(disk, "/home/features/hello.feature",
      "Feature: Hello\n  Scenario: Hi\n    Given the page says hello\n")
    :ok = Moss.Computer.Disk.write(disk, "/home/code/steps/hello.lua", good)
    :ok = Computer.agree(id, "/home/features/hello.feature")
    Computer.run(id, "test")

    Req.Test.stub(Moss.Fetch, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      sent = Jason.decode!(body)

      case conn.request_path do
        "/api/alpha/decisions" ->
          options = Map.keys(sent["questions"]["next"]["criteria"])
          choice = if "undo" in options, do: "undo", else: "write_steps"
          Agent.update(calls, &(&1 ++ [{:jev, options, choice}]))
          answers = %{"next" => %{"choice" => choice, "probabilities" => %{choice => 0.9}}}
          answers = if sent["questions"]["cause"], do: Map.put(answers, "cause", %{"choice" => "the_steps"}), else: answers
          Req.Test.json(conn, %{"answers" => answers})

        "/v1/chat/completions" ->
          bad = %{"cmd" => "test", "files" => %{"code/steps/hello.lua" => ~s|test.step("the page says hello", function(w) test.ok(false) end)\n|}}
          Req.Test.json(conn, %{"usage" => %{}, "choices" => [%{"message" => %{"tool_calls" => [%{"id" => "c",
            "type" => "function", "function" => %{"name" => "computer", "arguments" => Jason.encode!(bad)}}]}}]})
      end
    end)

    Moss.Computer.Agent.run(id, "Make me a hello page.", max_steps: 2)
    assert [{:jev, first, "write_steps"}, {:jev, second, "undo"}] = Agent.get(calls, & &1)
    refute "undo" in first
    assert "undo" in second
    assert Computer.run(id, "cat code/steps/hello.lua").out == good
    rows = Log.rows(:sys.get_state(Computer.whereis(id)).disk.conn, ["Outcome"])
    assert [_, note] = for(%{"args" => [at, _, note | _]} <- rows, String.contains?(at, "/step/"), do: note)
    assert note =~ "Test after: 1 of 1 pass (before: 0 of 1)."
  end

  # looking is using: a look that only opened the page did nothing, and publishing still waits on a real one
  test "a look that never submits the form is no look", %{id: id} do
    Computer.run(id, "help")
    disk = :sys.get_state(Computer.wake!(id)).disk
    :ok = Moss.Computer.Disk.write(disk, "/home/features/hello.feature",
      "Feature: Hello\n  Scenario: Hi\n    Given the page says hello\n")
    :ok = Moss.Computer.Disk.write(disk, "/home/code/steps/hello.lua",
      ~s|test.step("the page says hello", function(w) test.ok(true) end)\n|)
    :ok = Moss.Computer.Disk.write(disk, "/home/ui/index.lui", "<p>hello</p>\n")
    :ok = Computer.agree(id, "/home/features/hello.feature")
    Computer.run(id, "test")

    Req.Test.stub(Moss.Fetch, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      sent = Jason.decode!(body)

      case conn.request_path do
        "/api/alpha/decisions" ->
          answers = %{"next" => %{"choice" => "look_at_app", "probabilities" => %{"look_at_app" => 0.9}}}
          answers = if sent["questions"]["cause"], do: Map.put(answers, "cause", %{"choice" => "unclear"}), else: answers
          Req.Test.json(conn, %{"answers" => answers})

        "/v1/chat/completions" ->
          Req.Test.json(conn, %{"usage" => %{}, "choices" => [%{"message" => %{"tool_calls" => [%{"id" => "c",
            "type" => "function", "function" => %{"name" => "computer", "arguments" => ~s({"cmd": "open app"})}}]}}]})
      end
    end)

    Moss.Computer.Agent.run(id, "Make me a hello page.", max_steps: 1)
    rows = Log.rows(:sys.get_state(Computer.whereis(id)).disk.conn, ["Outcome"])
    assert ["no_effect"] = for(%{"args" => [at, o | _]} <- rows, String.contains?(at, "/step/"), do: o)
  end

  # and using it shows what was typed: a form whose action keeps nothing makes the look broken; one line of commands
  # (open app; type ...; click Add) is read command by command
  test "a look is complete only when what it typed shows on the page after it submits", %{id: id} do
    keeps = "function post.add(req) d:exec(\"insert into p values (?)\", req.form.name) end"
    assert look(id <> "a", "function post.add(req) end", ["open app", ~s(type "Plant name" "Pothos"), "submit Add"]) == "broken"
    assert look(id <> "b", keeps, ["open app; type Plant Pothos; click Add; page"]) == "complete"

    # and still there when the page is opened again: rows kept in a module's table, not its database, are not
    memory = "local mem = require(\"mem\")\nfunction post.add(req) table.insert(mem.items, req.form.name) end"
    page = "{% for _, n in ipairs(mem.items) do %}<p>{{ n }}</p>{% end %}"
    assert look(id <> "c", memory, ["open app; type 1 Pothos; submit 1"], page) == "broken"
  end

  defp look(id, action, cmds, list \\ nil) do
    Computer.run(id, "help")
    disk = :sys.get_state(Computer.wake!(id)).disk
    :ok = Moss.Computer.Disk.write(disk, "/home/features/hello.feature",
      "Feature: Hello\n  Scenario: Hi\n    Given the page says hello\n")
    :ok = Moss.Computer.Disk.write(disk, "/home/code/steps/hello.lua",
      ~s|test.step("the page says hello", function(w) test.ok(true) end)\n|)
    :ok = Moss.Computer.Disk.write(disk, "/home/ui/index.lui", """
    <lua>
    local d = db.open("data/p.dbl")
    d:exec("create table if not exists p (name text)")
    #{action}
    </lua>
    <form post="add"><input name="name" placeholder="Plant name"/><button>Add</button></form>
    #{list || ~s|{% for _, r in ipairs(d:query("select * from p")) do %}<p>{{ r.name }}</p>{% end %}|}
    """)
    :ok = Moss.Computer.Disk.write(disk, "/home/code/mem.lua", "local M = { items = {} }\nreturn M\n")
    :ok = Computer.agree(id, "/home/features/hello.feature")
    Computer.run(id, "test")

    Req.Test.stub(Moss.Fetch, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      sent = Jason.decode!(body)

      case conn.request_path do
        "/api/alpha/decisions" ->
          answers = %{"next" => %{"choice" => "look_at_app", "probabilities" => %{"look_at_app" => 0.9}}}
          answers = if sent["questions"]["cause"], do: Map.put(answers, "cause", %{"choice" => "unclear"}), else: answers
          Req.Test.json(conn, %{"answers" => answers})

        "/v1/chat/completions" ->
          calls =
            for {cmd, n} <- Enum.with_index(cmds) do
              %{"id" => "c#{n}", "type" => "function",
                "function" => %{"name" => "computer", "arguments" => Jason.encode!(%{"cmd" => cmd})}}
            end

          Req.Test.json(conn, %{"usage" => %{}, "choices" => [%{"message" => %{"tool_calls" => calls}}]})
      end
    end)

    Moss.Computer.Agent.run(id, "Make me a hello page.", max_steps: 1)
    rows = Log.rows(:sys.get_state(Computer.whereis(id)).disk.conn, ["Outcome"])
    [outcome] = for(%{"args" => [at, o | _]} <- rows, String.contains?(at, "/step/"), do: o)
    outcome
  end

  # code owns the workflow: what belongs to one move is refused in another, and a page names the command that opens it
  test "a move's calls that belong to another move are not run" do
    lua = Moss.Lua.base()
    eval = fn code -> Lua.eval!(lua, code) |> elem(0) end
    assert eval.(~s|return require("moss.world").refused("look_at_app", { cmd = "mail send rock-1 < files/r.org" })|) ==
             ["mail belongs to the answer_task move"]
    assert eval.(~s|return require("moss.world").refused("answer_task", { cmd = "mail send rock-1 -m x" })|) == []
    assert eval.(~s|return require("moss.world").refused("fix_failure", { cmd = "test", files = { ["features/a.feature"] = "" } })|) ==
             ["writing features/a.feature belongs to the write_feature move"]
    assert [why] = eval.(~s|return require("moss.world").refused("write_page", { cmd = "check", files = { ["apps/p/ui/index.lui"] = "" } })|)
    assert why =~ "outside the app: it lives in /home"
    assert eval.(~s|return require("moss.world").open("/house-plants/")|) == ["open app/house-plants"]
    assert eval.(~s|return require("moss.world").open("/")|) == ["open app"]

    # a failure reworded with no more scenarios passing is a stall all the same; one more passing starts again
    stall = fn b, a ->
      eval.(~s"""
      local req = { repeats = 1 }
      local function f(p, why) return { pages = {}, tests = { passed = p, total = 3, failing = { why }, undefined = {} } } end
      require("moss.world").after(req, f(#{b}), f(#{a}))
      return req.repeats
      """)
    end
    assert stall.(~s|1, "x: wanted 0"|, ~s|1, "x: wanted 0, got 1"|) == [2]
    assert stall.(~s|1, "x: wanted 0"|, ~s|2, "y: wanted 0"|) == [0]

    # one move Mercury could not fill is a service's bad minute: stopping waits for a second
    unfilled = ~s|{ verb = "fix_failure", outcome = "broken", note = "Filling the move failed: mercury unreachable" }|
    troubled = fn steps -> eval.(~s|return require("moss.world").troubled({ facts = { pages = {} }, steps = #{steps} }, 0)|) end
    assert troubled.("{ #{unfilled} }") == [false]
    assert troubled.("{ #{unfilled}, #{unfilled} }") == [true]
    assert eval.(~s|return require("moss.world").tidy("publish", { cmd = "publish expense_tracker", cwd = "x" }).cmd|) ==
             ["publish"]
    assert eval.(~s|return require("moss.world").tidy("write_code", { cmd = "test", files = '{"code/a.lua": "x"}' }).files["code/a.lua"]|) == ["x"]
    assert eval.(~s|return require("moss.world").tidy("write_code", { cmd = "test", files = "not json" }).files|) == [nil]
  end

  test "once shipped the task is answered: thinking or stopping only after an answer that failed" do
    options = fn steps, since ->
      Lua.eval!(Moss.Lua.base(), """
      local world = require("moss.world")
      local host = { facts = function() return { features = { { path = "features/a.feature", stage = "shipped" } },
        pages = {}, shipped = true, publishes = 1 } end }
      local q = world.new(host, {}).question({ req = { steps = #{steps}, publishes0 = #{since} } })
      local out = {}
      for name in pairs(q.options) do out[#out + 1] = name end
      table.sort(out)
      return table.concat(out, " ")
      """)
      |> elem(0)
      |> hd()
    end

    assert options.("{ { verb = 'publish', outcome = 'complete' } }", 0) == "answer_task"
    assert options.("{ { verb = 'answer_task', outcome = 'broken' } }", 0) == "answer_task blocked think"

    # and a task that began with the app already shipped changes it: the change moves, not the answer
    assert options.("{}", 1) == "read_help think write_code write_feature write_page write_steps"
  end

  # Tablua issue #1, M5: no deadlock class. A green app (every scenario passing, every page answering, no empty
  # step) always has a way on, whatever the stalls, the last move or the run: to publish (or first to use the app,
  # when it changed since it was used), or, while checks use steps of the app's own, to write the feature
  test "a green app can always reach publish, using the app, or the feature" do
    stuck =
      Lua.eval!(Moss.Lua.base(), """
      local world = require("moss.world")
      local stuck = {}
      for _, steps in ipairs({ "page", false }) do
        for _, own in ipairs({ true, false }) do
          for _, looked in ipairs({ true, false }) do
            for repeats = 0, 10 do
              for _, last in ipairs({ "think", "look_at_app", "write_code", "undo", "fix_failure" }) do
                local host = { facts = function() return { features = { { path = "features/a.feature", stage = "agreed" } },
                  pages = { { path = "/", status = 200 } }, empty_steps = 0,
                  tests = { passed = 2, total = 2, failing = {}, undefined = {}, checked = own and { "x is done" } or {} } } end }
                local req = { steps = { { n = 1, verb = last, outcome = "complete" } }, repeats = repeats, looked = looked }
                local q = world.new(host, { steps = steps or nil }).question({ req = req })
                local o = q.options or {}
                local way = o.write_feature or o.publish or (not looked and o.look_at_app)
                -- and only that: looking, thinking or testing again changes no check (own_checks_first)
                if steps == "page" and own then way = o.write_feature and not (o.look_at_app or o.think or o.run_test) end
                if not way then
                  stuck[#stuck + 1] = ("%s own=%s looked=%s repeats=%d last=%s stage=%s"):format(tostring(steps),
                    tostring(own), tostring(looked), repeats, last, tostring(req.stage))
                end
              end
            end
          end
        end
      end
      return table.concat(stuck, " / ")
      """)
      |> elem(0)
      |> hd()

    assert stuck == ""
  end

  # M5: each gate but the fixed ones can be turned off for a run, for an A/B (world/gates.lua)
  test "a gate turned off for a run holds nothing back, and a fixed gate cannot be turned off" do
    offered = fn run ->
      Lua.eval!(Moss.Lua.base(), """
      local world = require("moss.world")
      local host = { facts = function() return { features = { { path = "features/a.feature", stage = "agreed" } },
        pages = { { path = "/", status = 200 } }, empty_steps = 0,
        tests = { passed = 1, total = 2, failing = { "a: When I open the page: no page" }, undefined = {} } } end }
      local req = { steps = { { n = 1, verb = "think", outcome = "complete" } } }
      local q = world.new(host, #{run}).question({ req = req })
      return tostring(q.options.think ~= nil) .. " " .. tostring(q.options.undo ~= nil)
      """)
      |> elem(0)
      |> hd()
    end

    assert offered.("{}") == "false false"
    assert offered.(~s|{ gates_off = "think_twice,undo_regressed" }|) == "true false"
  end

  test "a page-steps run is not ready while a check uses a step of the app's own" do
    stage = fn run ->
      Lua.eval!(Moss.Lua.base(), """
      local world = require("moss.world")
      local host = { facts = function() return { features = { { path = "features/a.feature", stage = "agreed" } },
        pages = { { path = "/", status = 200 } }, empty_steps = 0,
        tests = { passed = 1, total = 1, failing = {}, undefined = {}, checked = { 'Yoga is done' } } } end }
      local req = { steps = {} }
      world.new(host, #{run}).question({ req = req })
      return req.stage .. ": " .. req.why
      """)
      |> elem(0)
      |> hd()
    end

    # what rank mode ranks: the moves the question offers, and the share passing, kept with each step
    assert Lua.eval!(Moss.Lua.base(), """
           local world = require("moss.world")
           local host = { facts = function() return { features = { { path = "features/a.feature", stage = "agreed" } },
             pages = { { path = "/", status = 200 } }, empty_steps = 0,
             tests = { passed = 1, total = 4, failing = { 'x' }, undefined = {} } } end }
           local w, req = world.new(host, {}), { steps = {} }
           local names = w.allowed({ req = req })
           return table.concat(names, " ") .. " " .. req.pass
           """)
           |> elem(0)
           |> hd() ==
             "blocked fix_failure look_at_app plan read_help rewrite run_check run_test think write_code write_page write_steps 0.25"

    assert stage.("{}") =~ "ready"
    assert stage.(~s|{ steps = "page" }|) =~ ~s|building: 1 checks use steps of the app's own, not the page's: write_feature rewrites each as I see "x" or I see "x" for "row", in the words the page shows (Yoga is done)|

    # and writing the feature, the one move that can change them, is offered at once
    offered =
      Lua.eval!(Moss.Lua.base(), """
      local world = require("moss.world")
      local host = { facts = function() return { features = { { path = "features/a.feature", stage = "agreed" } },
        pages = { { path = "/", status = 200 } }, empty_steps = 0,
        tests = { passed = 1, total = 1, failing = {}, undefined = {}, checked = { 'Yoga is done' } } } end }
      local q = world.new(host, { steps = "page" }).question({ req = { steps = {} } })
      return q.options.write_feature ~= nil
      """)
      |> elem(0)
      |> hd()

    assert offered
  end

  test "there is no agent without both minds", %{id: id} do
    System.delete_env("OPENROUTER_API_KEY")
    assert %{outcome: "error", why: why} = Moss.Computer.Agent.run(id, "Make me a hello page.")
    assert why =~ "no Jev key"
  end
end

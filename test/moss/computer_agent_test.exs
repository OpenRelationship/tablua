defmodule Moss.ComputerAgentTest do
  # The computer's own agent (Moss.Computer.Agent over Arock's library/agent), with Jev and Mercury answered by
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

  test "Jev decides every step before Mercury fills it, and the person's agreement is waited for", %{calls: calls, id: id} do
    run = Moss.Computer.Agent.run(id, "Make me a hello page.", at: "org:rock/mail/1")

    assert run.outcome == "waiting"
    assert run.why == "waiting for the person's agreement to the feature"
    log = Agent.get(calls, & &1)

    # first Jev, offered only what a computer with no feature allows; then Mercury, told Jev's move
    assert [{:jev, first, "write_feature"}, {:mercury, fill} | waits] = log
    assert Enum.sort(first) == ["blocked", "read_help", "think", "write_feature"]
    [system, turn] = fill["messages"]
    assert system["role"] == "system" and system["content"] =~ "<critical_rules>"
    assert String.ends_with?(String.trim(system["content"]), "</critical_rules>")
    assert turn["content"] =~ "<next_move>\nwrite_feature: "
    assert fill["tool_choice"] == "required" and fill["temperature"] == 0.6
    assert [%{"function" => %{"strict" => true}}] = fill["tools"]

    # the feature written and not agreed: only waiting, or changing it, is offered; Mercury is not asked to wait
    assert [{:jev, offered, "wait_for_agreement"} | _] = waits
    assert Enum.sort(offered) == ["blocked", "think", "wait_for_agreement", "write_feature"]
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
  end

  # the same failure through two fixes: fix_failure is taken off the table until Jev has the agent think it through
  test "a fix that leaves the same failure did nothing, and twice running it waits on thinking", %{calls: calls, id: id} do
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
          choice = if "fix_failure" in options, do: "fix_failure", else: "think"
          Agent.update(calls, &(&1 ++ [{:jev, options, choice}]))
          probabilities = Map.new(options, &{&1, if(&1 == choice, do: 0.9, else: 0.1 / (length(options) - 1))})
          # the cause, asked beside the move while something fails: the steps
          cause = if sent["questions"]["cause"], do: %{"cause" => %{"choice" => "the_steps", "probabilities" => %{"the_steps" => 0.8}}}, else: %{}
          Req.Test.json(conn, %{"answers" => Map.put(cause, "next", %{"choice" => choice, "probabilities" => probabilities})})

        "/v1/chat/completions" ->
          message =
            if sent["tools"],
              do: %{"tool_calls" => [%{"id" => "c", "type" => "function",
                "function" => %{"name" => "computer", "arguments" => ~s({"cmd": "status"})}}]},
              else: %{"content" => "The step checks nothing real; write the app's code first."}

          Req.Test.json(conn, %{"usage" => %{}, "choices" => [%{"message" => message}]})
      end
    end)

    Moss.Computer.Agent.run(id, "Make me a hello page.", max_steps: 4)
    jev = for {:jev, offered, choice} <- Agent.get(calls, & &1), do: {"fix_failure" in offered, choice}
    assert jev == [{true, "fix_failure"}, {true, "fix_failure"}, {false, "think"}, {true, "fix_failure"}]

    # and straight after thinking, thinking again is not offered
    [_, _, {:jev, third, _}, {:jev, fourth, _}] = Agent.get(calls, & &1)
    assert "think" in third and "think" not in fourth

    # each fix's note says it left the same failure, and its outcome is that it did nothing
    rows = Log.rows(:sys.get_state(Computer.whereis(id)).disk.conn, ["Outcome"])
    steps = for %{"args" => [at, outcome, note | _]} <- rows, String.contains?(at, "/step/"), do: {outcome, note}
    assert [{"no_effect", n1}, {"no_effect", n2}, {"complete", _}, {"no_effect", _}] = steps
    assert n1 =~ "] Cause placed in the_steps. Test after: 0 of 1 pass (before: 0 of 1). The same failure as before this step (1 changes"
    assert n2 =~ "(2 changes running have left it): Hi: Given the page says hello: /home/code/steps/hello.lua:1: no hello"
  end

  # Jev's none-of-these: twice running, the run ends blocked, with what is missing in Mercury's words
  test "Jev can say no move can make progress, and twice running that ends the run blocked", %{id: id} do
    Req.Test.stub(Moss.Fetch, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      sent = Jason.decode!(body)

      case conn.request_path do
        "/api/alpha/decisions" ->
          Req.Test.json(conn, %{"answers" => %{"next" => %{"choice" => "blocked", "probabilities" => %{"blocked" => 0.9}}}})

        "/v1/chat/completions" ->
          assert sent["messages"] |> hd() |> Map.get("content") =~ "none of its moves can make progress"
          Req.Test.json(conn, %{"usage" => %{}, "choices" => [%{"message" => %{"content" => "The filler answers 400 every time."}}]})
      end
    end)

    run = Moss.Computer.Agent.run(id, "Make me a hello page.")
    assert %{outcome: "blocked", why: "blocked: The filler answers 400 every time.", steps: 2} = run
    rows = Log.rows(:sys.get_state(Computer.whereis(id)).disk.conn, ["Outcome"])
    assert [{"blocked", "Blocked: The filler" <> _}, {"blocked", _}] =
             for(%{"args" => [at, o, note | _]} <- rows, String.contains?(at, "/step/"), do: {o, note})
  end

  # a page that does not answer says why in the facts both minds read, not its status alone
  test "a page that does not answer carries its error in the facts", %{id: id} do
    Computer.run(id, "help")
    disk = :sys.get_state(Computer.wake!(id)).disk
    :ok = Moss.Computer.Disk.write(disk, "/home/ui/index.lui", "<lua>\n  local d = nil\n</lua>\n<p>{{ d.name }}</p>\n")
    assert [%{"path" => "/", "status" => 500, "error" => error}] = Computer.agent(id, :facts, ["org:x"])["pages"]
    assert error =~ "index.lui"
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
  end

  test "once shipped the task is answered: thinking or stopping only after an answer that failed" do
    options = fn steps ->
      Lua.eval!(Moss.Lua.base(), """
      local world = require("moss.world")
      local host = { facts = function() return { features = { { path = "features/a.feature", stage = "shipped" } },
        pages = {}, shipped = true } end }
      local q = world.new(host, {}).question({ req = { steps = #{steps} } })
      local out = {}
      for name in pairs(q.options) do out[#out + 1] = name end
      table.sort(out)
      return table.concat(out, " ")
      """)
      |> elem(0)
      |> hd()
    end

    assert options.("{ { verb = 'publish', outcome = 'complete' } }") == "answer_task"
    assert options.("{ { verb = 'answer_task', outcome = 'broken' } }") == "answer_task blocked think"
  end

  test "there is no agent without both minds", %{id: id} do
    System.delete_env("OPENROUTER_API_KEY")
    assert %{outcome: "error", why: why} = Moss.Computer.Agent.run(id, "Make me a hello page.")
    assert why =~ "no Jev key"
  end
end

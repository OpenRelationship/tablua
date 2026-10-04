defmodule Moss.EditsTest do
  # A run that edits rows (arock issue #1 M6b, world/edits.lua): the filler is offered edits to one unit at a time,
  # with the units each of the app's files holds listed in the move, and an edit is spliced into its file whole by
  # the harness (Arock's tablua.edit) before the call's command runs; each call is a Tablua action row. Jev and
  # Mercury are answered by Req.Test.
  use ExUnit.Case, async: false

  alias Moss.Computer

  setup do
    old = for k <- ~w(OPENROUTER_API_KEY INCEPTION_API_KEY PRIORLABS_API_KEY), into: %{}, do: {k, System.get_env(k)}
    System.put_env("OPENROUTER_API_KEY", "jev-key")
    System.put_env("INCEPTION_API_KEY", "mercury-key")
    System.delete_env("PRIORLABS_API_KEY")

    on_exit(fn ->
      for {k, v} <- old, do: if(v, do: System.put_env(k, v), else: System.delete_env(k))
    end)

    %{id: "edits-#{System.unique_integer([:positive])}", sent: start_supervised!({Agent, fn -> [] end})}
  end

  defp setup_app(id) do
    Computer.run(id, "help")
    disk = :sys.get_state(Computer.wake!(id)).disk
    :ok = Moss.Computer.Disk.write(disk, "/home/features/hello.feature",
      "Feature: Hello\n  Scenario: Hi\n    Given the page says hello\n")
    :ok = Moss.Computer.Disk.write(disk, "/home/code/steps/hello.lua",
      "-- the page's greeting\n" <> ~s|test.step("the page says hello", function(w) test.ok(false) end)\n|)
    :ok = Computer.agree(id, "/home/features/hello.feature")
    Computer.run(id, "test")
  end

  defp stub(sent, edits) do
    Req.Test.stub(Moss.Fetch, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      req = Jason.decode!(body)

      case conn.request_path do
        "/api/alpha/decisions" ->
          options = Map.keys(req["questions"]["next"]["criteria"])
          choice = if "fix_failure" in options, do: "fix_failure", else: "write_steps"
          answers = %{"next" => %{"choice" => choice, "probabilities" => %{choice => 0.9}}}
          answers = if req["questions"]["cause"], do: Map.put(answers, "cause", %{"choice" => "the_steps"}), else: answers
          Req.Test.json(conn, %{"answers" => answers})

        "/v1/chat/completions" ->
          Agent.update(sent, &(&1 ++ [req]))
          call = %{"cmd" => "test", "edits" => edits}
          Req.Test.json(conn, %{"usage" => %{}, "choices" => [%{"message" => %{"tool_calls" => [%{"id" => "c",
            "type" => "function", "function" => %{"name" => "computer", "arguments" => Jason.encode!(call)}}]}}]})
      end
    end)
  end

  defp actions(id) do
    {:ok, rows} = Computer.agent(id, :sql, ["select op, target, exit from tablua_action order by n, i", []])
    rows
  end

  test "an edit to one step is spliced into its file, and is an action row", %{id: id, sent: sent} do
    setup_app(id)
    good = ~s|test.step("the page says hello", function(w) test.ok(true) end)|
    stub(sent, [%{"file" => "code/steps/hello.lua", "unit" => "the page says hello", "source" => good}])

    Moss.Computer.Agent.run(id, "Make me a hello page.", max_steps: 1, edits: "rows")

    [req] = Agent.get(sent, & &1)
    [tool] = req["tools"]
    assert tool["function"]["parameters"]["properties"]["edits"]
    user = List.last(req["messages"])["content"]
    assert user =~ "code/steps/hello.lua: the page says hello"
    assert Computer.run(id, "cat code/steps/hello.lua").out == "-- the page's greeting\n" <> good <> "\n"
    assert Computer.run(id, "test").code == 0
    assert [%{"op" => "edit_unit", "target" => "code/steps/hello.lua#the page says hello", "exit" => 0}] = actions(id)
  end

  test "an edit that would not compile is refused and its command never runs", %{id: id, sent: sent} do
    setup_app(id)
    stub(sent, [%{"file" => "code/steps/hello.lua", "unit" => "the page says hello", "source" => "test.step(("}])

    Moss.Computer.Agent.run(id, "Make me a hello page.", max_steps: 1, edits: "rows")

    assert Computer.run(id, "cat code/steps/hello.lua").out =~ "test.ok(false)"
    assert [%{"op" => "run", "exit" => 1}] = actions(id)
  end

  test "a run that writes files whole is offered no edits", %{id: id, sent: sent} do
    setup_app(id)
    stub(sent, [])

    Moss.Computer.Agent.run(id, "Make me a hello page.", max_steps: 1)

    [req] = Agent.get(sent, & &1)
    refute hd(req["tools"])["function"]["parameters"]["properties"]["edits"]
    refute List.last(req["messages"])["content"] =~ "The units an edit can name"
  end
end

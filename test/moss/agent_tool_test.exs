defmodule Moss.AgentToolTest do
  # Goal 4's proof (Arock PROJECT.md §14.7): a model, given only its own computer, learns the Lua SDK from `help lua`,
  # specifies a small tool in Gherkin, builds it to green on its own computer, and the tool then does what was asked
  # when this test drives it. Live: it calls a model on OpenRouter with the host's key, which never reaches the
  # computer. Run with `mix test --only agent`; MOSS_AGENT_MODEL picks the model.
  use ExUnit.Case, async: false

  alias Moss.Computer

  @moduletag :agent
  @moduletag timeout: 3_600_000

  # its own folders, so another test run (which empties the shared ones) cannot pull its disk from under it
  setup_all do
    dir = Path.join(System.tmp_dir!(), "moss-agent-#{System.unique_integer([:positive])}")

    for {key, sub} <- [work_dir: "work", local_objects: "runs"],
        do: Application.put_env(:moss, key, Path.join(dir, sub))

    Application.put_env(:moss, :objects, :local)
    :ok
  end

  @task """
  You have your own computer, reached through the `computer` tool. It is not Linux: its commands are few (run
  `help`), and its one language is Lua (run `help lua` for the library, which is all a script can use).

  Build a small tool there, in /home/plants:

    lua plants.lua add <name> <every-days>     starts watering <name> every <every-days> days; prints "added <name>"
    lua plants.lua water <name> <YYYY-MM-DD>   records a watering on that day; prints "watered <name>"
    lua plants.lua due <YYYY-MM-DD>            prints, one per line and sorted by name, each plant due on or before
                                               that day (never watered counts as due), as "<name> <days overdue>"
    lua plants.lua import <file.csv>           adds every row of a CSV with the header name,every
    lua plants.lua report <file.html>          writes an HTML page listing every plant and its last watering

  Keep the plants in a database, plants.db in the folder the tool runs in. Before writing plants.lua, write its behaviour as Gherkin in
  features/plants.feature and the steps in Lua in features/steps.lua, run with require("test"); the steps may
  call the tool's functions directly or run its commands' logic, as you see fit. You are done when
  `cd /home/plants && lua features/steps.lua` reports every scenario passed. Then answer with one word: DONE.
  """

  @tool %{
    type: "function",
    function: %{
      name: "computer",
      description:
        "Runs one command line on your computer and returns its status, stdout and stderr. `files` (path -> text) " <>
          "are written first, relative to `cwd` (default /home); use it to create or replace files.",
      parameters: %{
        type: "object",
        properties: %{
          cmd: %{type: "string", description: "the command line, e.g. `lua features/steps.lua`"},
          cwd: %{type: "string"},
          files: %{type: "object", additionalProperties: %{type: "string"}}
        },
        required: ["cmd"]
      }
    }
  }

  test "an agent builds a small tool end to end on its own computer" do
    key = Moss.Keys.get("jev") || flunk("no OPENROUTER_API_KEY")
    model = System.get_env("MOSS_AGENT_MODEL") || "moonshotai/kimi-k2.7-code"
    id = "agent-tool-#{System.unique_integer([:positive])}"
    Moss.Owners.claim(id, "tester")
    Computer.run(id, "mkdir -p /home/plants")

    messages = [%{role: "user", content: @task}]
    {turns, calls} = loop(key, model, id, messages, 0, 0)
    IO.puts("\n#{model}: #{turns} turns, #{calls} commands on #{id}")

    # its own tests, green
    own = Computer.run(id, "cd /home/plants && lua features/steps.lua")
    IO.puts(own.out)
    assert own.code == 0 or own.out =~ ~r/(\d+) of \1 scenarios passed/

    # and the tool does what was asked, driven from here
    sh = fn line -> Computer.run(id, "cd /home/plants && " <> line) end
    assert %{code: 0} = sh.("rm plants.db")

    Computer.exec(id, %{
      "cwd" => "/home/plants",
      "cmd" => "true",
      "files" => %{"check.csv" => "name,every\nmoss,7\n\"basil, sweet\",2\n"}
    })

    assert %{code: 0, out: "added fern\n"} = sh.("lua plants.lua add fern 3")
    assert %{code: 0} = sh.("lua plants.lua import check.csv")
    assert %{code: 0, out: "watered fern\n"} = sh.("lua plants.lua water fern 2026-10-01")
    assert %{code: 0} = sh.("lua plants.lua water moss 2026-10-01")
    assert %{code: 0} = sh.("lua plants.lua water 'basil, sweet' 2026-10-01")

    assert %{code: 0, out: ""} = sh.("lua plants.lua due 2026-10-02")
    assert %{code: 0, out: "basil, sweet 0\n"} = sh.("lua plants.lua due 2026-10-03")
    assert %{code: 0, out: "basil, sweet 3\nfern 2\n"} = sh.("lua plants.lua due 2026-10-06")

    assert %{code: 0} = sh.("lua plants.lua report report.html")
    assert %{code: 0, out: page} = sh.("cat report.html")
    assert page =~ "fern" and page =~ "2026-10-01" and page =~ "basil, sweet"
  end

  defp loop(key, model, id, messages, turns, calls) do
    msg = ask(key, model, messages)

    case msg["tool_calls"] do
      [_ | _] = tcs ->
        results =
          for tc <- tcs do
            args = Jason.decode!(tc["function"]["arguments"] || "{}")
            r = Computer.exec(id, args)
            IO.puts("$ #{args["cmd"]}  -> #{r["code"]}#{files(args)}")

            %{
              role: "tool",
              tool_call_id: tc["id"],
              content:
                "status #{r["code"]}\n--- stdout\n#{clip(r["stdout"])}\n--- stderr\n#{clip(r["stderr"])}"
            }
          end

        loop(
          key,
          model,
          id,
          messages ++ [Map.delete(msg, "finish")] ++ results,
          turns + 1,
          calls + length(tcs)
        )

      _ ->
        said = msg["content"] || ""
        IO.puts("agent (#{msg["finish"]}): #{String.slice(said, 0, 400)}")

        # a turn without a command is the end only when it says so; otherwise it is asked to go on
        if said =~ ~r/\bDONE\b/ do
          {turns + 1, calls}
        else
          go_on = %{
            role: "user",
            content: "Keep going until `lua features/steps.lua` passes, then answer DONE."
          }

          loop(key, model, id, messages ++ [Map.delete(msg, "finish"), go_on], turns + 1, calls)
        end
    end
  end

  defp ask(key, model, messages) do
    resp =
      Req.post!("https://openrouter.ai/api/v1/chat/completions",
        auth: {:bearer, key},
        json: %{model: model, messages: messages, tools: [@tool], max_tokens: 16_000},
        receive_timeout: 300_000,
        retry: :transient
      )

    case resp.body do
      %{"choices" => [%{"message" => msg} | _]} ->
        Map.take(msg, ["role", "content", "tool_calls"])

      other ->
        flunk("the model answered #{resp.status}: #{inspect(other) |> String.slice(0, 400)}")
    end
  end

  defp files(%{"files" => f}) when is_map(f) and map_size(f) > 0,
    do: "  (wrote #{Enum.join(Map.keys(f), ", ")})"

  defp files(_), do: ""

  defp clip(s) when byte_size(s) > 8000, do: binary_part(s, 0, 8000) <> "\n... (cut)"
  defp clip(s), do: s
end

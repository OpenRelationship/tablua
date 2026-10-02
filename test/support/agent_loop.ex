defmodule Moss.AgentLoop do
  @moduledoc """
  The live agent tests' loop: a model on OpenRouter, given one tool, `computer`, that runs a command line on its
  own computer. Its context is its computer's own (Arock's feature file-kinds): `help` and its procedures,
  the org files in org/procedures/, read from the computer as the run starts. The host's key never reaches the computer. A turn without a command ends the loop only when it
  says DONE; otherwise the model is told `go_on` and asked again.
  """
  alias Moss.Computer

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

  @doc "Gives the model its own folders, so another test run (which empties the shared ones) leaves its disk be."
  def own_folders do
    dir = Path.join(System.tmp_dir!(), "moss-agent-#{System.unique_integer([:positive])}")

    for {key, sub} <- [work_dir: "work", local_objects: "runs"],
        do: Application.put_env(:moss, key, Path.join(dir, sub))

    Application.put_env(:moss, :objects, :local)
  end

  def model, do: System.get_env("MOSS_AGENT_MODEL") || "moonshotai/kimi-k2.7-code"

  @doc "Runs the task to DONE on computer `id`; returns {turns, the command lines it ran}."
  def run(id, task, go_on) do
    %{turns: turns, cmds: cmds} = run(id, task, go_on, [])
    {turns, cmds}
  end

  @doc """
  The same, with `between` (a function of the computer's id, called after each turn: the person's part, say)
  and `max_turns` (default 150): `%{turns, cmds, cost}`, cost being OpenRouter's own in USD.
  """
  def run(id, task, go_on, opts) do
    key = Moss.Keys.get("jev") || raise "no OPENROUTER_API_KEY"
    messages = [%{role: "system", content: context(id)}, %{role: "user", content: task}]
    Process.put(:agent_cost, 0.0)

    Process.put(:agent_opts, %{
      between: opts[:between] || fn _ -> :ok end,
      max: opts[:max_turns] || 150
    })

    {turns, cmds} =
      try do
        loop(key, model(), id, messages, go_on, 0, [])
      catch
        {:stopped, turns, cmds} -> IO.puts("agent: stopped at #{turns} turns") && {turns, cmds}
      end

    cost = Process.get(:agent_cost)

    IO.puts(
      "\n#{model()}: #{turns} turns, #{length(cmds)} commands on #{id}, $#{Float.round(cost, 4)}"
    )

    %{turns: turns, cmds: Enum.reverse(cmds), cost: cost}
  end

  @doc "The model's context, from its computer: `help`, then each of its procedures."
  def context(id) do
    help = Computer.run(id, "help").out
    %{out: names} = Computer.run(id, "ls org/procedures")

    procedures =
      for name <- String.split(names, "\n", trim: true),
          do: Computer.run(id, "cat org/procedures/#{name}").out

    Enum.join([help | procedures], "\n")
  end

  defp loop(key, model, id, messages, go_on, turns, cmds) do
    if turns >= Process.get(:agent_opts, %{max: 150}).max,
      do: throw({:stopped, turns, cmds})

    msg = ask(key, model, messages)
    Process.get(:agent_opts, %{between: fn _ -> :ok end}).between.(id)

    case msg["tool_calls"] do
      [_ | _] = tcs ->
        {results, ran} =
          Enum.map_reduce(tcs, cmds, fn tc, ran ->
            # a model cut off mid-call sends half its JSON: it is told so, as a command's error would be
            {args, r} =
              case Jason.decode(tc["function"]["arguments"] || "{}") do
                {:ok, %{} = args} ->
                  {args, Computer.exec(id, args)}

                _ ->
                  {%{"cmd" => "(arguments not valid JSON)"},
                   %{
                     "code" => 2,
                     "stdout" => "",
                     "stderr" =>
                       "the tool call's arguments were not valid JSON, perhaps cut off: send smaller files"
                   }}
              end

            IO.puts("$ #{args["cmd"]}  -> #{r["code"]}#{files(args)}")

            {%{
               role: "tool",
               tool_call_id: tc["id"],
               content:
                 "status #{r["code"]}\n--- stdout\n#{clip(r["stdout"])}\n--- stderr\n#{clip(r["stderr"])}"
             }, [args["cmd"] | ran]}
          end)

        loop(key, model, id, messages ++ [msg] ++ results, go_on, turns + 1, ran)

      _ ->
        said = msg["content"] || ""
        IO.puts("agent: #{String.slice(said, 0, 400)}")

        # DONE alone on its last line: "then I will answer DONE" is not done
        if said
           |> String.trim()
           |> String.split("\n")
           |> List.last()
           |> String.trim()
           |> Kernel.in(["DONE", "DONE."]),
           do: {turns + 1, cmds},
           else:
             loop(
               key,
               model,
               id,
               messages ++ [msg, %{role: "user", content: go_on}],
               go_on,
               turns + 1,
               cmds
             )
    end
  end

  defp ask(key, model, messages) do
    resp =
      Req.post!("https://openrouter.ai/api/v1/chat/completions",
        auth: {:bearer, key},
        json: %{
          model: model,
          messages: messages,
          tools: [@tool],
          max_tokens: 16_000,
          usage: %{include: true}
        },
        receive_timeout: 300_000,
        retry: :transient
      )

    case resp.body do
      %{"choices" => [%{"message" => msg} | _]} = body ->
        cost = get_in(body, ["usage", "cost"]) || 0
        Process.put(:agent_cost, (Process.get(:agent_cost) || 0.0) + cost)
        Map.take(msg, ["role", "content", "tool_calls"])

      other ->
        raise "the model answered #{resp.status}: #{inspect(other) |> String.slice(0, 400)}"
    end
  end

  defp files(%{"files" => f}) when is_map(f) and map_size(f) > 0,
    do: "  (wrote #{Enum.join(Map.keys(f), ", ")})"

  defp files(_), do: ""

  defp clip(s) when is_binary(s) and byte_size(s) > 8000,
    do: binary_part(s, 0, 8000) <> "\n... (cut)"

  defp clip(s), do: s
end

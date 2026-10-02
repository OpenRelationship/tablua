defmodule Moss.AgentLoop do
  @moduledoc """
  The live agent tests' loop: Mercury (Arock's writer, PROJECT.md §14.6), on Inception's own API and no other, given one tool, `computer`, that runs a command line on its
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

  # Mercury is the agent: no setting picks another model, so a run is never measured on one it will not ship with.
  # A comparison is named by the caller, from this list only, and every run says which model it was.
  @model "mercury-2.5"
  @api "https://api.inceptionlabs.ai/v1/chat/completions"
  # prices in USD per token, from each provider's own model list (2026-10-02): input, cached input, output
  @models %{
    "mercury-2.5" => %{api: @api, key: "mercury", price: {0.04e-6, 0.004e-6, 0.15e-6}},
    # a comparison (owner, 2026-10-02): Ling 3.0 Flash VL on OpenRouter, which reports each request's cost itself
    "inclusionai/ling-3.0-flash-vl" => %{
      api: "https://openrouter.ai/api/v1/chat/completions",
      key: "jev",
      price: {0.021e-6, 0.021e-6, 0.0616e-6}
    }
  }

  def model, do: @model
  def api, do: @api
  def models, do: Map.keys(@models)

  @doc "What a request cost, from its usage: the provider's own figure when it gives one, else its list price."
  def cost(usage, model \\ @model)
  def cost(%{"cost" => c}, _model) when is_number(c), do: c

  def cost(usage, model) do
    {input, cached, output} = @models[model].price
    hit = get_in(usage, ["prompt_tokens_details", "cached_tokens"]) || 0

    ((usage["prompt_tokens"] || 0) - hit) * input + hit * cached +
      (usage["completion_tokens"] || 0) * output
  end

  @doc "Runs the task to DONE on computer `id`; returns {turns, the command lines it ran}."
  def run(id, task, go_on) do
    %{turns: turns, cmds: cmds} = run(id, task, go_on, [])
    {turns, cmds}
  end

  @doc """
  The same, with `between` (a function of the computer's id, called after each turn: the person's part, say)
  `max_turns` (default 150), `effort` (reasoning effort: low, medium or high; the provider's own default, about
  medium for Mercury, when nil) and `model` (a comparison from `models/0`; Mercury when nil):
  `%{model, turns, cmds, cost, errors, tokens}`: cost in USD, errors
  the commands that exited non-zero, tokens `{prompt, cached, completion}` summed over the run.
  """
  def run(id, task, go_on, opts) do
    model = opts[:model] || @model
    spec = @models[model] || raise "#{model} is not a model the loop runs: #{inspect(models())}"
    key = Moss.Host.key(spec.key) || raise "no key for #{model} (Moss.Host.key #{spec.key})"

    messages = [%{role: "system", content: context(id)}, %{role: "user", content: task}]
    Process.put(:agent_cost, 0.0)
    Process.put(:agent_errors, 0)
    Process.put(:agent_tokens, {0, 0, 0})

    Process.put(:agent_opts, %{
      between: opts[:between] || fn _ -> :ok end,
      max: opts[:max_turns] || 150,
      effort: opts[:effort]
    })

    {turns, cmds} =
      try do
        loop({key, model}, model, id, messages, go_on, 0, [])
      catch
        {:stopped, turns, cmds} -> IO.puts("agent: stopped at #{turns} turns") && {turns, cmds}
      end

    cost = Process.get(:agent_cost)

    IO.puts(
      "\n#{model}: #{turns} turns, #{length(cmds)} commands on #{id}, $#{Float.round(cost, 4)}"
    )

    %{
      model: model,
      turns: turns,
      cmds: Enum.reverse(cmds),
      cost: cost,
      errors: Process.get(:agent_errors),
      tokens: Process.get(:agent_tokens)
    }
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
            if r["code"] != 0, do: Process.put(:agent_errors, Process.get(:agent_errors, 0) + 1)

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

  defp ask({key, _}, model, messages) do
    spec = @models[model]

    resp =
      Req.post!(spec.api,
        auth: {:bearer, key},
        json:
          effort(spec.api, %{model: model, messages: messages, tools: [@tool], max_tokens: 16_000}),
        receive_timeout: 300_000,
        retry: :transient
      )

    case resp.body do
      %{"choices" => [%{"message" => msg} | _]} = body ->
        usage = body["usage"] || %{}
        Process.put(:agent_cost, (Process.get(:agent_cost) || 0.0) + cost(usage, model))
        {p, c, o} = Process.get(:agent_tokens, {0, 0, 0})
        hit = get_in(usage, ["prompt_tokens_details", "cached_tokens"]) || 0

        Process.put(
          :agent_tokens,
          {p + (usage["prompt_tokens"] || 0), c + hit, o + (usage["completion_tokens"] || 0)}
        )

        Map.take(msg, ["role", "content", "tool_calls"])

      other ->
        raise "the model answered #{resp.status}: #{inspect(other) |> String.slice(0, 400)}"
    end
  end

  # Inception takes reasoning_effort; OpenRouter its own reasoning field, and reports cost when asked
  defp effort(@api, body) do
    case Process.get(:agent_opts, %{})[:effort] do
      nil -> body
      e -> Map.put(body, :reasoning_effort, e)
    end
  end

  defp effort(_openrouter, body) do
    body = Map.put(body, :usage, %{include: true})

    case Process.get(:agent_opts, %{})[:effort] do
      nil -> body
      e -> Map.put(body, :reasoning, %{effort: e})
    end
  end

  defp files(%{"files" => f}) when is_map(f) and map_size(f) > 0,
    do: "  (wrote #{Enum.join(Map.keys(f), ", ")})"

  defp files(_), do: ""

  defp clip(s) when is_binary(s) and byte_size(s) > 8000,
    do: binary_part(s, 0, 8000) <> "\n... (cut)"

  defp clip(s), do: s
end

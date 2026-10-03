defmodule Moss.Computer.Agent do
  @moduledoc """
  The computer's own agent (Arock PROJECT.md §1, §14; feature file-kinds): Arock's harness (Arock's
  `library/agent`: Jev decides each step, Mercury fills it, TabPFN reaches Jev once it is stuck) with this
  computer as its world (`priv/lua/world`). It builds what a task asks as an app, agreed to shipped, and answers
  the task; the person's part (agreeing to a feature, the yes to publish) is theirs, and the run waits for it.

  `run/3` drives it a step a call (tv-labs lua keeps no garbage collector, so no call lives long): each call
  rebuilds the agent from what the last saved. The Lua runs in the caller's process and reaches the computer
  through it like any client (`Moss.Computer.exec/2`, and `agent/3` for the facts and the log), so the computer
  is never blocked on itself.

  Every decision is a Decide row and every step's outcome an Outcome row, at the step's address, and the run says
  how many calls Jev, Mercury and TabPFN took and what they cost.
  """
  alias Moss.{Computer, Log}
  alias Moss.Computer.{Board, Disk, Script}

  # the rows agent.memory folds, and the decisions
  @memory [
    "Request",
    "Step",
    "Sure",
    "Outcome",
    "Controls",
    "Chose Control",
    "Predict",
    "Predict Call",
    "Fit",
    "Prune Memory",
    "Decide"
  ]

  @doc """
  Runs `task` (the ask, in the person's words) on computer `id` until Jev answers, the run stops, or it waits on
  the person three steps running with nothing changed. Options: `at` (the task's address, the key every
  decision is joined to its outcome by; `org:<id>` by default), `between` (a function of `id`, called after each
  step: the person's part, in a test), `max_steps` (150), `filler` (an OpenRouter model to fill
  Jev's moves in Mercury's place) and `decider` (a System One model in Jev's), each for a comparison. Gives `%{outcome, why, steps, counts}`, outcome being
  "done", "blocked", "waiting", "stopped" or "error".
  """
  def run(id, task, opts \\ []) do
    ctx = %{
      "task" => task,
      "at" => opts[:at] || "org:#{id}",
      "help" => help(id),
      "procedures" => procedures(id),
      "filler" => opts[:filler],
      "decider" => opts[:decider]
    }

    loop(id, ctx, nil, opts[:between] || fn _ -> :ok end, opts[:max_steps] || 150, 0, 0, nil)
  end

  defp loop(_id, _ctx, _saved, _between, max, n, _waits, counts) when n >= max,
    do: %{outcome: "stopped", why: "#{max} steps", steps: n, counts: counts}

  defp loop(id, ctx, saved, between, max, n, waits, counts) do
    case Moss.Lua.call(:agent, [saved, ctx], computer: id, agent: id) |> counted() do
      {:ok, ["done", why, _saved, counts]} ->
        %{outcome: "done", why: why, steps: n + 1, counts: counts}

      # Jev said twice running that no move can make progress: what is missing, in Mercury's words
      {:ok, ["blocked", why, _saved, counts]} ->
        %{outcome: "blocked", why: why, steps: n + 1, counts: counts}

      {:ok, ["wait", what, saved, counts]} ->
        between.(id)

        if waits >= 2,
          do: %{outcome: "waiting", why: "waiting for #{what}", steps: n + 1, counts: counts},
          else: loop(id, ctx, saved, between, max, n + 1, waits + 1, counts)

      {:ok, [_act, _verb, saved, counts]} ->
        between.(id)
        loop(id, ctx, saved, between, max, n + 1, 0, counts)

      {:error, why} ->
        %{outcome: "error", why: why, steps: n, counts: counts}
    end
  end

  # the counts as a map (Lua gives a table back as pairs)
  defp counted({:ok, [kind, detail, saved, counts]}), do: {:ok, [kind, detail, saved, Map.new(counts || [])]}
  defp counted(other), do: other

  # Mercury's knowledge base: the index and every topic the building uses, so it never has to guess an API
  # (static for the run, so Inception's prefix cache holds it)
  @topics ["feature", "code", "lua date", "data", "page", "loop", "manifest", "mail", "classes"]

  defp help(id) do
    Enum.map_join(["help" | Enum.map(@topics, &"help #{&1}")], "\n", &Computer.run(id, &1).out)
  end

  defp procedures(id) do
    %{out: names} = Computer.run(id, "ls org/procedures")

    names
    |> String.split("\n", trim: true)
    |> Enum.map_join("\n", &Computer.run(id, "cat org/procedures/#{&1}").out)
  end

  # ------------------------------------------------------------------------------------------------------------
  # In the computer's own process (Moss.Computer.agent/3).

  @doc "The rows agent.memory folds, with their task."
  def events(state), do: Log.rows(state.disk.conn, @memory)

  @doc "A row on the computer's log, through arock-log (which takes any keyword and checks the ones it knows)."
  def append(state, task, keyword, args, actor) do
    {:ok, _} = Log.alog(state.disk.conn, "append", [task, keyword, args, actor])
    :ok
  end

  @doc """
  What the agent's stages are worked out from, the computer's own account: each feature's stage, the last test
  run of them all (nil when one wants a run), step definitions with an empty body, each page and what it answers,
  whether publishing waits on the person, whether everything shipped, and whether the task at `at` is answered.
  """
  def facts(state, at) do
    board = Board.board(state)
    scopes = Board.scopes(state.disk)
    log = Log.events(state.disk.conn, ["Ask Person", "Outcome"])

    %{
      "features" => for(r <- board, do: %{"path" => Board.rel(r.path), "stage" => r.stage}),
      "tests" => tests(board),
      "empty_steps" => empty_steps(state.disk, scopes),
      "pages" => pages(state, scopes),
      "asked" => asked?(log),
      "publishes" => length(Log.events(state.disk.conn, ["Publish Artifact"])),
      "shipped" => board != [] and Enum.all?(board, &(&1.stage == "shipped")),
      "answered" =>
        Moss.Host.board(state.id) =~ ~r/\*\* DONE .*\n:PROPERTIES:\n:ID: #{Regex.escape(at)}\n/
    }
  end

  defp tests(board) do
    if board == [] or Enum.any?(board, &(&1.run == nil or &1.stage in ["asked", "written", "agreed"])) do
      nil
    else
      runs = Enum.map(board, & &1.run)

      %{
        "passed" => Enum.sum(Enum.map(runs, &(&1["passed"] || 0))),
        "total" => Enum.sum(Enum.map(runs, &(&1["total"] || 0))),
        # a feature with no scenarios fails check every run, and no change to code can fix it (a notes change
        # wrote one and rewrote its code fifty times)
        "failing" =>
          for(
            r <- runs,
            f <- r["failing"] || [],
            do: "#{f["scenario"]}: #{f["step"]}: #{f["why"]}"
          ) ++
            for(
              r <- board,
              (r.run["total"] || 0) == 0,
              do: "#{Board.rel(r.path)} has no scenarios: write them in it (Scenario: and its steps)"
            ),
        "undefined" => Enum.flat_map(runs, &(&1["undefined"] || []))
      }
    end
  end

  # a step whose function does nothing: `function(w, name) end`
  defp empty_steps(disk, scopes) do
    for scope <- scopes,
        path <- Board.files(disk, scope <> "/code/steps", ".lua"),
        {:ok, text} <- [Disk.read(disk, path)],
        is_binary(text),
        reduce: 0,
        do: (n -> n + length(Regex.scan(~r/function\s*\([^)]*\)\s*end/, text)))
  end

  # each page, served as the person's browser asks for it
  defp pages(state, scopes) do
    for scope <- scopes,
        page <- Board.pages(state.disk, scope),
        not String.contains?(page, "/_") do
      path = url(page)
      page_file = page

      {status, headers, body, _} =
        Script.serve(%{"method" => "GET", "path" => path}, %{
          state
          | disk: %{state.disk | actor: "user"}
        })

      # a page that does not answer says why (its file, line and error), for both minds to read; one that does
      # names each {{ e }} that showed nothing
      page = %{"path" => path, "status" => status}
      page = if n = headers["x-moss-nil"], do: Map.put(page, "nils", n), else: page

      # a page that opens a database itself shows what no step tests: the steps test the code module
      own_db =
        case Disk.read(state.disk, page_file) do
          {:ok, text} when is_binary(text) -> String.contains?(text, "db.open(")
          _ -> false
        end

      page = if own_db, do: Map.put(page, "own_db", Board.rel(page_file)), else: page
      if status == 200, do: page, else: Map.put(page, "error", body |> IO.iodata_to_binary() |> String.slice(0, 400))
    end
  end

  defp url(page) do
    page
    |> String.replace_prefix("/home/apps/", "/")
    |> String.replace_prefix("/home", "")
    |> String.replace("/ui/", "/")
    |> String.replace_suffix("index.lui", "")
    |> String.replace_suffix(".lui", "")
  end

  # publishing asked the person, and they have not answered since
  defp asked?(log) do
    last = fn match -> log |> Enum.filter(match) |> List.last() end
    ask = last.(fn {_, k, args} -> k == "Ask Person" and hd(args) == "publish" end)

    answer =
      last.(fn {_, k, [line | rest]} ->
        k == "Outcome" and String.starts_with?(line, "publish") and rest != [] and
          hd(rest) in ["yes", "no"]
      end)

    ask != nil and (answer == nil or elem(answer, 0) < elem(ask, 0))
  end
end

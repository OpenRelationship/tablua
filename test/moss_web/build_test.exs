defmodule MossWeb.BuildTest do
  # Arock's feature file-kinds, goal 11: from a spoken ask (heard by `just tool eval build`, which runs this), an
  # agent on a fresh computer builds the app, agreed to shipped, with no human edits. The ask arrives as a task in
  # the post; the agent works from its procedures and help alone (Moss.AgentLoop); the person's part is only
  # theirs to give: agreeing to each feature as written, and saying yes to the publish. Live and paid:
  # `mix test --only build`; AROCK_ASK is the ask, AROCK_BUILD_OUT where the measures go, MOSS_AGENT_MODEL the model.
  use MossWeb.ConnCase, async: false

  alias Moss.{Computer, Log, Mail}
  alias Moss.Computer.Board

  @moduletag :build
  @moduletag timeout: 7_200_000

  @ask "I'd like a little app for my house plants. It should list each plant with when I last watered it, " <>
         "let me add a plant, and let me mark one as watered today."

  setup_all do
    Moss.AgentLoop.own_folders()
    :ok
  end

  defp state(id), do: :sys.get_state(Computer.wake!(id))

  # the person: agrees to each feature as it stands, says yes to what waits for them; never edits
  defp person(id) do
    st = state(id)

    for %{stage: "written", path: path} <- Board.board(st) do
      :ok = Computer.agree(id, path)
      IO.puts("person: agreed to #{Board.rel(path)}")
    end

    answered = Process.get(:answered, MapSet.new())

    for {seq, _, [_tool, line]} <- Log.events(st.disk.conn, ["Ask Person"]),
        seq not in answered do
      Process.put(:answered, MapSet.put(Process.get(:answered, MapSet.new()), seq))
      IO.puts("person: yes to #{line}")
      Computer.answer(id, line, true)
    end

    :ok
  end

  test "an agent builds the app from a spoken ask, agreed to shipped" do
    n = System.unique_integer([:positive])
    {rock, id} = {"rock-#{n}", "plants-#{n}"}
    ask = System.get_env("AROCK_ASK") || @ask
    :ok = Moss.Owners.claim(id, "tester")
    for {a, b} <- [{rock, id}, {id, rock}], do: :ok = Mail.route(a, b, "audit")
    for c <- [rock, id], do: Computer.run(c, "true")

    # the rock hands the ask on as it was heard: one computer, so there is nothing to route
    {:delivered, task} =
      Mail.post(rock, id, "", "* TODO Build the app the person asked for\n#{ask}\n")

    address = "org:#{rock}/mail/#{task}"
    started = System.monotonic_time(:millisecond)

    run =
      Moss.AgentLoop.run(
        id,
        "You have mail: a task from #{rock}. Work on it as your procedures say, until what it asks has shipped " <>
          "and you have answered the task. Then answer with one word: DONE.",
        "Keep going as your procedures say: the task is done when it has shipped and you have answered it.",
        between: &person/1,
        max_turns: 150
      )

    person(id)
    seconds = (System.monotonic_time(:millisecond) - started) / 1000
    st = state(id)
    board = Board.board(st)
    shipped = Log.events(st.disk.conn, ["Publish Artifact"]) != []
    answered = Mail.board(rock) =~ ~r/\*\* DONE .*\n:PROPERTIES:\n:ID: #{Regex.escape(address)}/

    # its pages, as the person opens them
    pages = for scope <- Board.scopes(st.disk), p <- Board.pages(st.disk, scope), do: p

    served =
      for p <- pages, not String.contains?(p, "/_") do
        path =
          p
          |> String.replace_prefix("/home/apps/", "/")
          |> String.replace_prefix("/home", "")
          |> String.replace("/ui/", "/")
          |> String.replace_suffix("index.lui", "")
          |> String.replace_suffix(".lui", "")

        {path, elem(Computer.serve(id, %{"method" => "GET", "path" => path}), 0)}
      end

    agreements = length(Log.events(st.disk.conn, ["Agree Feature"]))

    # what a computer costs, measured as §14.6 measures it: asleep, then woken by a command
    :ok = Computer.sleep(id)
    file = Path.join([Application.fetch_env!(:moss, :work_dir), "computers", id <> ".sqlite"])
    {wake_us, _} = :timer.tc(fn -> Computer.run(id, "true") end)
    {:memory, memory} = Process.info(Computer.whereis(id), :memory)

    result = %{
      model: Moss.AgentLoop.model(),
      ask: ask,
      shipped: shipped,
      answered: answered,
      turns: run.turns,
      commands: length(run.cmds),
      cost: run.cost,
      seconds: seconds,
      features: for(r <- board, do: %{path: Board.rel(r.path), stage: r.stage}),
      pages: for({p, s} <- served, do: %{path: p, status: s}),
      agreements: agreements,
      wake_ms: wake_us / 1000,
      memory_kb: div(memory, 1024),
      file_kb: div(File.stat!(file).size, 1024)
    }

    IO.puts("\n" <> Jason.encode!(result, pretty: true))
    if out = System.get_env("AROCK_BUILD_OUT"), do: File.write!(out, Jason.encode!(result))

    assert shipped, "it never shipped"
    assert answered, "the task was never answered DONE"
    assert board != [] and Enum.all?(board, &(&1.stage == "shipped")), inspect(board)
    assert served != [] and Enum.all?(served, &(elem(&1, 1) == 200)), inspect(served)
  end
end

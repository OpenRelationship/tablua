defmodule Moss.Computer.Loop do
  @moduledoc """
  The build loop's commands (Arock's feature file-kinds): `test` runs features by their steps, `check` compiles
  every page, checks every manifest and runs every feature, `status` is the board (`Moss.Computer.Board`), and
  `publish` waits for green and then for the person's yes.

      test [feature ...]   every feature, or those named; red is status 1, and an undefined step prints its stub
      check                every page, manifest and feature: one line per failure, file and line first
      status               each feature's stage, as org
      publish [app]        the app (or the folder's scope): refused unless every agreed feature is green

  Each feature's run is an Outcome on the log (green or red, what failed, and the digest of its scope's files
  then); the person's agreement is an Agree Feature, a publish they said yes to a Publish Artifact.
  """
  alias Moss.Computer.{Board, Disk, Manifest, Script}
  alias Moss.Log

  @help """
  The build loop: spec, steps, pages, green, then the person's yes.

      new feature <name>   features/<name>.feature, one scenario, in the person's words
      test [feature ...]   runs features by the steps in code/steps/*.lua; a step no pattern matches prints
                           the stub to paste: test.step("the list holds {int} plants", function(w, n1) ... end)
                           holes: {int} {number} {string} {word} {}; test.eq(got, want), test.ok(v) in a step
      check                every page compiled, every manifest checked, every feature run; file:line first
      status               each feature's stage: written, agreed (the person said yes), red, green, shipped
      publish [app]        refused unless every agreed feature is green; then the person is asked
      new page|code|task|note|letter|manifest|app <name>   the smallest working file of that kind

  A feature changed after the person agreed goes back to written; any change to its app's features, code or
  pages wants a new run before it is green again. Every run is an Outcome on the log.
  """

  def help, do: @help

  def names, do: ~w(test check status publish)

  def run("test", args, state), do: test(paths(args, state), state)
  def run("check", _args, state), do: check(state)
  def run("status", _args, state), do: {0, Board.status(state), "", state}
  def run("publish", args, state), do: publish(scope(args, state), state, [])

  # the features named, or every one on the computer
  defp paths([], state),
    do: Enum.flat_map(Board.scopes(state.disk), &Board.features(state.disk, &1))

  defp paths(args, state), do: Enum.map(args, &Disk.norm(&1, state.cwd))

  defp test(paths, state) do
    missing = Enum.reject(paths, &match?({:ok, _}, Disk.read(state.disk, &1)))

    cond do
      missing != [] ->
        {2, "", "test: no such feature: #{Enum.map_join(missing, ", ", &Board.rel/1)}\n", state}

      paths == [] ->
        {0, "no features yet: new feature <name> writes one, in features/\n", "", state}

      true ->
        {out, err, runs} = run_features(paths, state)
        red = for r <- runs, r.outcome == "red", do: Board.rel(r.feature)

        summary =
          if red == [],
            do: "green: #{length(runs)} of #{length(runs)} features passed\n",
            else: "red: #{Enum.join(red, ", ")}\n"

        {if(red == [], do: 0, else: 1), out <> summary, err, state}
    end
  end

  # each scope's features run together, each run logged: {out, err, [%{feature, outcome}]}
  defp run_features(paths, state) do
    paths
    |> Enum.group_by(&Board.scope_of/1)
    |> Enum.reduce({"", "", []}, fn {scope, features}, {out, err, runs} ->
      {_, o, e, reports} = Script.loop("test", scope, features, state)
      digest = Board.digest(state.disk, scope)
      reported = Map.new(reports, &{&1["feature"], &1})

      logged =
        for f <- features do
          r = reported[f] || %{"failing" => [%{"step" => "", "why" => "the run stopped: #{e}"}]}
          logged(state, f, r, digest)
        end

      {out <> o, err <> e, runs ++ logged}
    end)
  end

  defp logged(state, feature, r, digest) do
    failing = list(r["failing"])
    undefined = list(r["undefined"])
    broken = list(r["broken"])
    green = failing == [] and undefined == [] and broken == [] and (r["total"] || 0) > 0
    outcome = if green, do: "green", else: "red"

    detail =
      Jason.encode!(%{
        digest: digest,
        passed: r["passed"] || 0,
        total: r["total"] || 0,
        failing: failing ++ Enum.map(broken, &%{"step" => "a step file", "why" => &1}),
        undefined: undefined
      })

    :ok = Log.append(state.disk.conn, state.id, "Outcome", [feature, outcome, detail, ""], "host")
    %{feature: feature, outcome: outcome}
  end

  defp check(state) do
    scopes = Board.scopes(state.disk)

    pages =
      for scope <- scopes,
          pages = Board.pages(state.disk, scope),
          pages != [],
          {_, _, _, reports} = Script.loop("pages", scope, pages, state),
          r <- reports,
          r["why"],
          do: Board.rel(r["why"]) <> "\n"

    manifests =
      for scope <- scopes,
          path = scope <> "/manifest.org",
          {:ok, text} <- [Disk.read(state.disk, path)],
          line <- Manifest.check(text),
          do: "#{Board.rel(path)}:#{line}\n"

    {code, out, err, state} = test(paths([], state), state)
    failures = pages ++ manifests
    head = if failures == [], do: "pages and manifests: ok\n", else: Enum.join(failures)
    {if(failures == [] and code == 0, do: 0, else: 1), head <> out, err, state}
  end

  @doc "The scope an app names, or the folder's own."
  def scope([app | _], _state), do: "/home/apps/" <> app
  def scope([], state), do: Board.scope_of(state.cwd)

  @doc """
  `publish`: refused, naming each agreed feature not green; otherwise the person is asked (Ask Person), and
  their yes (`asked: true`) is a Publish Artifact.
  """
  def publish(scope, state, opts) do
    rows = for r <- Board.board(state), r.scope == scope, do: r
    red = for r <- rows, r.stage not in ~w(written green shipped), do: r
    line = if scope == "/home", do: "publish", else: "publish " <> Path.basename(scope)
    name = Board.address(state, scope)

    cond do
      not match?({:ok, %{dir: true}}, Disk.stat(state.disk, scope)) ->
        {2, "", "publish: no app #{Path.basename(scope)}\n", state}

      red != [] ->
        why = Enum.map_join(red, "", &"  #{Board.rel(&1.path)} is #{&1.stage}\n")
        {1, "", "publish: refused, every agreed feature must be green first:\n" <> why, state}

      Keyword.get(opts, :asked, false) ->
        :ok = Log.append(state.disk.conn, state.id, "Publish Artifact", [name], "user")
        {0, "published #{name}\n", "", state}

      true ->
        :ok = Log.append(state.disk.conn, state.id, "Ask Person", ["publish", line], "agent")
        {3, "", "publish waits for the person's yes: they are asked\n", state}
    end
  end

  # loop's JSON writes an empty list as {}
  defp list(l) when is_list(l), do: l
  defp list(_), do: []
end

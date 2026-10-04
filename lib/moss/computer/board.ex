defmodule Moss.Computer.Board do
  @moduledoc """
  Each feature's stage (Arock's feature file-kinds, "The build loop"), derived from its files, its last run and
  the log; no plan is stored.

      asked     the .feature says what is asked and has no scenario yet (a writ's service no app offers, Arock
                feature notes: the person asked for it in words; the loop writes its scenarios)
      written   the .feature exists, and the person has not agreed to it as it stands
      agreed    the person agreed (Agree Feature, for this text), and it has not run since its files changed
      red       agreed, and its last run failed or has undefined steps
      green     agreed, its last run passed, and no file of its scope changed since
      shipped   green, and published with the person's yes (Publish Artifact)

  A scope is the computer (/home) or one app (/home/apps/<app>); its files are its features, code and pages.
  """
  alias Moss.Computer.Disk
  alias Moss.Log

  @doc "Every scope on the computer: /home, then each app's folder."
  def scopes(disk) do
    apps = for %{name: n, dir: true} <- list(disk, "/home/apps"), do: "/home/apps/" <> n
    ["/home" | apps]
  end

  @doc "The scope `path` is in."
  def scope_of(path) do
    case Regex.run(~r"\A/home/apps/[a-z0-9][a-z0-9-]*", path) do
      [scope] -> scope
      _ -> "/home"
    end
  end

  @doc "The scope's features, by path."
  def features(disk, scope), do: files(disk, scope <> "/features", ".feature")

  @doc "The scope's pages, by path: org pages (org and Lua) and .lui ones."
  def pages(disk, scope),
    do: Enum.sort(files(disk, scope <> "/ui", ".org") ++ files(disk, scope <> "/ui", ".lui"))

  @doc "What publishing `scope` is called on the log: the app's address, or the computer's."
  def address(state, "/home"), do: "org:" <> state.id
  def address(state, "/home/apps/" <> app), do: "org:#{state.id}/#{app}"

  @doc "A digest of everything a scope's run depends on: its features, code and pages."
  def digest(disk, scope) do
    paths =
      Enum.flat_map(~w(features code ui), &files(disk, "#{scope}/#{&1}", "")) |> Enum.sort()

    :crypto.hash(:sha256, for(p <- paths, {:ok, d} = Disk.read(disk, p), do: [p, 0, d, 0]))
    |> Base.encode16(case: :lower)
  end

  @doc "The SHA-256 of a feature's text, as Agree Feature records it."
  def text_digest(disk, path) do
    {:ok, text} = Disk.read(disk, path)
    :crypto.hash(:sha256, text) |> Base.encode16(case: :lower)
  end

  @doc "Each feature with its stage and last run: `[%{path, scope, stage, run}]`, in scope order."
  def board(state) do
    log = Log.events(state.disk.conn, ["Agree Feature", "Outcome", "Publish Artifact"])

    for scope <- scopes(state.disk), path <- features(state.disk, scope) do
      run = last(log, "Outcome", path)

      %{
        path: path,
        scope: scope,
        stage: stage(state, log, scope, path, run),
        run: run && run.detail
      }
    end
  end

  defp stage(state, log, scope, path, run) do
    agreed = last(log, "Agree Feature", path)
    shipped = last(log, "Publish Artifact", address(state, scope))

    cond do
      agreed == nil and asked?(state.disk, path) -> "asked"
      agreed == nil or hd(agreed.args) != text_digest(state.disk, path) -> "written"
      run == nil or run.seq < agreed.seq -> "agreed"
      run.outcome == "red" -> "red"
      run.detail["digest"] != digest(state.disk, scope) -> "agreed"
      shipped && shipped.seq > run.seq -> "shipped"
      true -> "green"
    end
  end

  @doc "Whether a feature only asks: it has no scenario yet."
  def asked?(disk, path) do
    case Disk.read(disk, path) do
      {:ok, text} -> not Regex.match?(~r/^\s*(Scenario|Scenario Outline|Scenario Template|Example):/m, text)
      _ -> false
    end
  end

  # the last event of `keyword` about `target`
  defp last(log, keyword, target) do
    Enum.reduce(log, nil, fn
      {seq, ^keyword, [^target | rest]}, _ -> event(keyword, seq, rest)
      _, acc -> acc
    end)
  end

  defp event("Outcome", seq, [outcome, detail | _]),
    do: %{seq: seq, outcome: outcome, detail: Jason.decode!(detail)}

  defp event(_, seq, rest), do: %{seq: seq, args: rest}

  @doc "`status`: the board as org, one entry per feature, its stage a tag and its failing steps below."
  def status(state) do
    case board(state) do
      [] ->
        "#+TITLE: status\n\nno features yet: new feature <name> writes one, in features/\n"

      rows ->
        "#+TITLE: status\n\n" <> Enum.map_join(rows, "", &entry(state, &1))
    end
  end

  defp entry(state, %{path: path, scope: scope, stage: stage, run: run}) do
    failing =
      for f <- (run && run["failing"]) || [],
          do: "- #{f["scenario"]}: #{f["step"]}: #{f["why"]}\n"

    undefined = for u <- (run && run["undefined"]) || [], do: "- no step matches: #{u}\n"
    pages = for p <- pages(state.disk, scope), do: rel(p)
    pages = if pages == [], do: "", else: "- pages: #{Enum.join(pages, ", ")}\n"
    "* #{rel(path)} :#{stage}:\n" <> Enum.join(Enum.uniq(failing ++ undefined)) <> pages
  end

  @doc "A path as the agent writes it, from /home."
  def rel("/home/" <> p), do: p
  def rel(p), do: p

  defp list(disk, dir) do
    case Disk.list(disk, dir) do
      {:ok, entries} -> entries
      _ -> []
    end
  end

  # the files under dir whose names end in ext, in path order
  @doc "The files under `dir` ending in `ext`, by path."
  def files(disk, dir, ext) do
    list(disk, dir)
    |> Enum.flat_map(fn
      %{name: n, dir: true} -> files(disk, "#{dir}/#{n}", ext)
      %{name: n} -> if String.ends_with?(n, ext), do: ["#{dir}/#{n}"], else: []
    end)
    |> Enum.sort()
  end
end

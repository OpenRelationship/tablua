defmodule Moss.Computer.Tools do
  @moduledoc """
  The computer's tools (Arock's feature `manifest`): each a headline in a manifest.org, run by name in the shell
  (`weather Lisbon`, `plants:seed`). `tools` lists them with what they do, their arguments and their reach.

  A run checks its arguments against their types, runs the tool's code in its folder (its app's, or /home) with
  them as `arg[1]...` and by name (`arg.city`), and carries the tool's reach: the requests the person granted
  (`Moss.Computer.Script.Http`). A tool marked ASK runs only after the person's yes: asked, it is an `Ask Person`
  event and nothing runs.
  """
  alias Moss.Computer.{Manifest, Script}
  alias Moss.Log

  @help """
  manifest.org: what this computer offers. /home/manifest.org lists the apps (an app folder not listed is not
  served) and the computer's tools; apps/<app>/manifest.org lists that app's tools, run as <app>:<tool>.

      * Apps
      - [[org:fern/plants]]

      * Tools
      ** weather
      :PROPERTIES:
      :RUN: code/weather.lua
      :NET: api.open-meteo.com
      :EVERY: daily 07:00
      :END:
      Pull the day's weather.
      - city :: string
      - days :: number = 3
      - units :: one of metric|imperial = metric
      - note :: string?

  A tool runs by its name (weather Lisbon); its code reads arg.city or arg[1]. tools lists them.
  Arguments: string, number, bool, one of a|b; = gives a default, ? makes one optional.
  Triggers: EVERY hourly, daily HH:MM, weekdays HH:MM, weekly Mon HH:MM, every 15m|2h|1d (UTC, or a clock's own
  offset: weekdays 07:00 UTC-07:00); the computer wakes for it. A tool with FROM is a writ's: the person's words make
  it, and it changes when the writ does.
  Reach is asked here and granted only by the person: NET <host, ...>, MAIL <address>, ACCOUNT <app>.
  ASK makes each run wait for the person's yes. Until they grant it, a fetch is refused with what to ask;
  removing a request takes its grant back. A lua run outside a tool reaches nothing beyond the computer.
  GRANTED is never written by you: the person's yes is kept on the log.
  """

  def help, do: @help

  @doc "The tool `name` names on this computer, or nil."
  def find(state, name) do
    if String.match?(name, ~r/\A[a-z0-9][a-z0-9:-]*\z/), do: Manifest.tool(state.disk, name)
  end

  @doc "`tools`: each tool, what it does, its arguments and its reach."
  def list(state) do
    m = Manifest.read(state.disk)
    grants = Manifest.grants(state.disk)

    out =
      for {name, t} <- Enum.sort(m.tools) do
        args = for a <- t.args, do: "  #{a["name"]} :: #{type(a)}\n"

        reach =
          for {r, v} <- Manifest.requests(t) do
            said =
              if MapSet.member?(grants, {name, r, v}),
                do: "granted",
                else: "asked, not granted yet"

            "  #{r} #{v}: #{said}\n"
          end

        marks =
          Enum.join(
            for({k, true} <- [ASK: t.ask, PUBLISH: t.publish], do: " #{k}") ++ triggers(t)
          )

        "#{name}#{marks}: #{t.description}\n" <> Enum.join(args) <> Enum.join(reach)
      end

    {0,
     if(out == [],
       do: "no tools yet: a headline under * Tools in manifest.org makes one\n",
       else: Enum.join(out)
     ), ""}
  end

  @doc "Runs `tool` with `args` (strings, as typed): `{code, out, err, state}`."
  def run(tool, args, stdin, state, opts \\ []) do
    case typed(tool.args, args) do
      {:error, why} ->
        {2, "", "#{tool.name}: #{why}\n", state}

      {:ok, named} ->
        if tool.ask and not Keyword.get(opts, :asked, false) do
          line = Enum.join([tool.name | args], " ")
          :ok = Log.append(state.disk.conn, state.id, "Ask Person", [tool.name, line], "agent")

          {3, "", "#{tool.name} waits for the person's yes (ASK): nothing ran; they are asked\n",
           state}
        else
          reach = %{
            tool: tool.name,
            asked: Manifest.requests(tool),
            granted: Manifest.granted(state.disk, tool)
          }

          run_state =
            Map.merge(state, %{cwd: Manifest.folder(tool), reach: reach, tool_args: named})

          {code, out, err, _} = Script.run([tool.run | args], stdin, run_state)
          {code, out, err, state}
        end
    end
  end

  # the arguments by name, each read as its type says, or why not
  defp typed(specs, args) do
    if length(args) > length(specs) do
      {:error,
       "takes #{length(specs)} argument(s): #{Enum.map_join(specs, ", ", &"#{&1["name"]} :: #{type(&1)}")}"}
    else
      Enum.with_index(specs)
      |> Enum.reduce_while({:ok, %{}}, fn {a, i}, {:ok, acc} ->
        case value(a, Enum.at(args, i)) do
          {:ok, nil} -> {:cont, {:ok, acc}}
          {:ok, v} -> {:cont, {:ok, Map.put(acc, a["name"], v)}}
          {:error, why} -> {:halt, {:error, why}}
        end
      end)
    end
  end

  defp value(%{"default" => d} = a, nil), do: value(Map.delete(a, "default"), d)
  defp value(%{"optional" => true}, nil), do: {:ok, nil}
  defp value(a, nil), do: {:error, "#{a["name"]} :: #{type(a)} is needed"}

  defp value(a, s) do
    case {a["type"], s} do
      {"string", s} ->
        {:ok, s}

      {"number", s} ->
        number(s) || {:error, "#{a["name"]} is a number, and #{s} is not"}

      {"bool", s} when s in ~w(true yes) ->
        {:ok, true}

      {"bool", s} when s in ~w(false no) ->
        {:ok, false}

      {"bool", s} ->
        {:error, "#{a["name"]} is true or false, not #{s}"}

      {"choice", s} ->
        if s in (a["choices"] || []),
          do: {:ok, s},
          else: {:error, "#{a["name"]} is #{type(a)}, not #{s}"}

      {t, _} ->
        {:error, "#{a["name"]} has a type the computer does not know: #{t}"}
    end
  end

  defp number(s) do
    case Float.parse(s) do
      {f, ""} -> {:ok, if(f == trunc(f), do: trunc(f), else: f)}
      _ -> nil
    end
  end

  defp type(%{"type" => "choice", "choices" => c}), do: "one of " <> Enum.join(c, "|")
  defp type(%{"type" => t}), do: t

  defp triggers(t),
    do:
      if(t.every, do: [" EVERY #{t.every}"], else: []) ++ if(t.on, do: [" ON #{t.on}"], else: [])
end

defmodule Moss.Computer.Writs do
  @moduledoc """
  The person's writs on their rock's computer (Arock's feature notes: prose that is code). A writ is the source and
  what it made is its build: a tool in a manifest that carries `:FROM: note-<n>@<version>#<bytes>` is the writ's,
  and changes when the writ does. So an agent's manifest that changes or drops such a tool is refused, naming the
  writ, and its wording is kept for the person as a suggestion in `/home/writs/suggestions.org`, which the Mac
  reads and offers in the writ. The person's writes (and the host's) pass; `/home/writs` is theirs alone
  (`Moss.Computer.Disk`), so an agent reads it and writes none of it.

  A suggestion is one org entry:

      * Suggestion for file-mail
      :PROPERTIES:
      :NOTE: note-3
      :TOOL: file-mail
      :FROM: note-3@2#1-62
      :AT: 2026-10-03T17:00:00Z
      :END:
      #+begin_src org
      ** file-mail
      ...the agent's text for the tool, or (removed)
      #+end_src
  """
  alias Moss.Computer.Disk

  @suggestions "/home/writs/suggestions.org"

  def suggestions, do: @suggestions

  @doc "`:ok`, or why an agent's manifest at `path` may not be written: it changes or drops a writ's tool."
  def check(%{actor: actor, app: false}, _path, _data) when actor in ["user", "host"], do: :ok

  def check(disk, path, data) do
    was =
      case Disk.read(disk, path) do
        {:ok, old} -> tools(old)
        _ -> %{}
      end

    now = tools(data)

    case for({name, text} <- was, from = from(text), now[name] != text, do: {name, from, now[name]}) do
      [] ->
        :ok

      touched ->
        for {name, from, proposed} <- touched, do: suggest(disk, name, from, proposed)

        {:error,
         Enum.map_join(touched, "\n", fn {name, from, _} ->
           "the tool #{name} comes from writ #{note(from)}; it changes when the writ does. Your wording is kept " <>
             "for the person as a suggestion (writs/suggestions.org)."
         end)}
    end
  end

  @doc """
  `:ok`, or why an agent may not remove or move `path`: writs/ is the person's, and a manifest (or an app's
  folder holding one) whose tools a writ made goes only when the writ does.
  """
  def guard(%{actor: actor, app: false}, _path) when actor in ["user", "host"], do: :ok

  def guard(disk, path) do
    if path == "/home/writs" or String.starts_with?(path, "/home/writs/") do
      {:error, "writs/ is the person's: their writs are read here, never written, moved or removed"}
    else
      Enum.reduce_while(manifests(disk, path), :ok, fn m, :ok ->
        case check(disk, m, "") do
          :ok -> {:cont, :ok}
          refused -> {:halt, refused}
        end
      end)
    end
  end

  # the manifests a removal or move of `path` takes with it
  defp manifests(disk, path) do
    apps =
      case Disk.list(disk, "/home/apps") do
        {:ok, entries} -> for %{name: n, dir: true} <- entries, do: "/home/apps/#{n}/manifest.org"
        _ -> []
      end

    ["/home/manifest.org" | apps]
    |> Enum.filter(&(&1 == path or String.starts_with?(&1, path <> "/")))
  end

  @doc "A manifest's tools, `name => its text` (its headline to the next), each with its trailing blank lines cut."
  def tools(text) do
    text
    |> String.split("\n")
    |> Enum.reduce({%{}, nil}, fn line, {acc, current} ->
      cond do
        String.starts_with?(line, "** ") ->
          name = line |> String.slice(3..-1//1) |> String.trim()
          {Map.put(acc, name, [line]), name}

        String.starts_with?(line, "* ") ->
          {acc, nil}

        current ->
          {Map.update!(acc, current, &[line | &1]), current}

        true ->
          {acc, current}
      end
    end)
    |> elem(0)
    |> Map.new(fn {name, lines} -> {name, lines |> Enum.reverse() |> Enum.join("\n") |> String.trim_trailing()} end)
  end

  @doc "The writ address a tool's text carries in `:FROM:`, or nil."
  def from(text) do
    case Regex.run(~r/^:FROM:\s*(\S+)\s*$/m, text) do
      [_, from] -> from
      _ -> nil
    end
  end

  # note-3@2#1-62 -> note-3
  defp note(from), do: from |> String.split("@") |> hd()

  defp suggest(disk, name, from, proposed) do
    host = %{disk | actor: "host"}

    old =
      case Disk.read(host, @suggestions) do
        {:ok, t} -> t
        _ -> ""
      end

    at = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    entry = """
    * Suggestion for #{name}
    :PROPERTIES:
    :NOTE: #{note(from)}
    :TOOL: #{name}
    :FROM: #{from}
    :AT: #{at}
    :END:
    #+begin_src org
    #{proposed || "(removed)"}
    #+end_src
    """

    Disk.write(host, @suggestions, old <> entry)
  end
end

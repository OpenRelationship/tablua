defmodule Moss.Computer.New do
  @moduledoc """
  `new <kind> <name>` (Arock's feature file-kinds): the smallest working file of a kind, written where the kind
  lives in the folder's scope (the computer's, or the app's it is in), for the agent to change rather than write
  from nothing. It never writes over a file.

      new feature plants    features/plants.feature, one scenario (test then prints the stubs for its steps)
      new page index        ui/index.lui, a page that renders, adds and removes
      new orgpage index     ui/index.org, the same page in org and Lua (sdk/orgpage.lua)
      new code water        code/water.lua
      new task|note|letter <name>   org/<name>.org, from org's own template
      new manifest          manifest.org
      new app plants        apps/plants/ui/index.lui, and the app listed in the root manifest
  """
  alias Moss.Computer.{Board, Disk, Script}

  @kinds ~w(feature page orgpage code task note letter manifest app)

  def run([kind | rest], state) when kind in @kinds do
    name = List.first(rest) || if(kind == "manifest", do: "manifest")
    # recipe_box or Recipe_Box is recipe-box: the name a file can have, not a refusal (a recipes run blocked on it)
    name = name && name |> String.downcase() |> String.replace(~r/[_\s]+/, "-")

    cond do
      name == nil or not Regex.match?(~r/\A[a-z0-9][a-z0-9-]{0,63}\z/, name) ->
        {2, "", "new #{kind}: give a name of lower-case letters, digits and dashes\n", state}

      true ->
        scope = Board.scope_of(state.cwd)
        write(kind, name, scope, state)
    end
  end

  def run(_, state),
    do: {2, "", "new: new <#{Enum.join(@kinds, "|")}> <name>\n", state}

  defp write("app", name, _scope, state) do
    scope = "/home/apps/" <> name

    with {0, out, "", state} <- write("page", "index", scope, state) do
      {0, out <> list_app(state, name), "", state}
    end
  end

  defp write(kind, name, scope, state) do
    path = scope <> "/" <> file(kind, name)

    case Disk.stat(state.disk, path) do
      {:ok, _} ->
        {1, "", "new: #{Board.rel(path)} is there already: change it\n", state}

      _ ->
        case Disk.write(state.disk, path, text(kind, name, scope, state)) do
          :ok -> {0, "wrote #{Board.rel(path)}\n", "", state}
          {:error, why} -> {1, "", "new: #{why}\n", state}
        end
    end
  end

  defp file("feature", n), do: "features/#{n}.feature"
  defp file("page", n), do: "ui/#{n}.lui"
  defp file("orgpage", n), do: "ui/#{n}.org"
  defp file("code", n), do: "code/#{n}.lua"
  defp file("manifest", _), do: "manifest.org"
  defp file(_org, n), do: "org/#{n}.org"

  defp text("feature", name, _, _) do
    """
    Feature: #{name}
      What it is for, in the person's words.

      Scenario: the first thing it does
        Given the #{name} is empty
        When the person adds "one"
        Then the #{name} holds 1 item
    """
  end

  defp text("page", _name, scope, state) do
    app = if scope == "/home", do: "items", else: Path.basename(scope)
    code = ~s|io.write(require("shroomi.lui").template(arg[1]))|
    {0, out, _, _} = Script.run(["-e", code, app], "", state)
    out
  end

  defp text("orgpage", _name, scope, state) do
    app = if scope == "/home", do: "items", else: Path.basename(scope)
    {0, out, _, _} = Script.run(["-e", ~s|io.write(require("orgpage").template(arg[1]))|, app], "", state)
    out
  end

  defp text("code", name, _, _) do
    """
    -- #{name}: what it does. Run it as `lua code/#{name}.lua`, or name it in manifest.org as a tool.
    print("#{name}", arg[1])
    """
  end

  defp text(kind, _name, _, state) do
    today = Date.utc_today() |> Date.to_iso8601()
    {:ok, [text]} = Moss.Lua.call("names", ["template", kind, state.id, today], %{})
    text
  end

  # the app listed in the root manifest, under * Apps
  defp list_app(state, name) do
    link = "- [[org:#{state.id}/#{name}]]"

    text =
      case Disk.read(state.disk, "/home/manifest.org") do
        {:ok, t} -> t
        _ -> ""
      end

    cond do
      String.contains?(text, link) ->
        ""

      String.contains?(text, "* Apps\n") ->
        :ok =
          Disk.write(
            state.disk,
            "/home/manifest.org",
            String.replace(text, "* Apps\n", "* Apps\n#{link}\n", global: false)
          )

        "listed in manifest.org\n"

      true ->
        :ok = Disk.write(state.disk, "/home/manifest.org", "* Apps\n#{link}\n\n" <> text)
        "listed in manifest.org\n"
    end
  end
end

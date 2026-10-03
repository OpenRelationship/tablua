defmodule Moss.Computer.Look.Command do
  @moduledoc """
  `look [--width N] [--dark|--light]`: the app's page in the front tab (or the computer's own app, `/`) laid out
  as its person would see it, and what they could not use named by its line in the page's source (Arock feature
  look): a control of no size, a control under another element, something running off the screen, text too faint
  to read. The width and theme are the browser's (`open app --width N --dark`) unless given here. Exit 1 when there
  are faults, so a check can run it.
  """
  alias MossBrowser.Look.Faults
  alias MossBrowser.Page.Attrs
  alias Moss.Computer.{Look, Pages}
  alias Moss.Computer.Browser.{Nav, Tabs}

  @app "http://app/"

  def run(args, state) do
    with {:ok, screen} <- Look.flags(args, Tabs.screen(state)),
         url = url(state),
         {:ok, r, state} <- Nav.fetch(state, url, lines: true) do
      case Look.look(url, r.body, screen) do
        {:ok, look} -> say(look, file(url, state), state)
        {:error, why} -> {1, "", "look: #{error(why)}\n", state}
      end
    else
      {:error, why} when is_binary(why) -> {2, "", "look: " <> why <> "\n", state}
      {:error, why} -> {6, "", "look: #{inspect(why)}\n", state}
    end
  end

  # the front tab's page when it is the computer's app, else the app's first page
  defp url(state) do
    case Tabs.front(state) do
      %{url: @app <> _ = url} -> url
      _ -> @app
    end
  end

  defp file(url, state) do
    path = URI.parse(url).path || "/"

    case Pages.route(path, state.disk) do
      {_, nil} -> "the page"
      {_, file} -> String.replace_prefix(file, "/home/", "")
    end
  end

  defp error(:no_look), do: "this node has no look module (mix moss.look)"
  defp error(:too_costly), do: "the page was too costly to lay out"
  defp error(why), do: "the page could not be laid out (#{why})"

  defp say(look, file, state) do
    lines = lines(look.tree, nil, %{})
    theme = if look.dark, do: ", dark", else: ""
    head = "#{file} at #{look.width} px#{theme}"

    case Faults.faults(look) do
      [] ->
        {0, "#{head}: nothing a person could not use\n", "", state}

      faults ->
        out =
          Enum.map_join(faults, fn f -> "  #{file}:#{lines[f.id] || "?"}  #{fault(f, lines, look)}\n" end)

        n = length(faults)
        {1, "#{head}: #{n} #{if n == 1, do: "fault", else: "faults"}\n" <> out, "", state}
    end
  end

  defp fault(%{kind: :unseen} = f, _lines, _look),
    do: "#{name(f.element)} cannot be seen: it is #{f.box.w} by #{f.box.h} px"

  defp fault(%{kind: :covered} = f, lines, _look),
    do: "#{name(f.element)} cannot be clicked: #{name(f.by)} (line #{lines[f.by_id] || "?"}) is over it"

  defp fault(%{kind: :off_screen, box: b} = f, _lines, look),
    do:
      "#{name(f.element)} runs off the screen: #{b.w} px wide, from #{b.x} to #{b.x + b.w} " <>
        "on a #{look.width} px screen"

  defp fault(%{kind: :faint} = f, _lines, _look),
    do: "#{name(f.element)} is too faint: #{f.color} on #{f.background}, #{f.ratio} to 1 (4.5 needed)"

  # an element by what a person would call it: a button's words, a field's name, a tag and its first words
  defp name({tag, attrs, kids}) do
    words = kids |> Attrs.words() |> String.trim() |> String.slice(0, 40)

    case tag do
      "button" -> ~s(button "#{words}")
      "a" -> ~s(link "#{words}")
      t when t in ~w(input select textarea) -> ~s(field "#{Attrs.attr(attrs, "name") || words}")
      t when words == "" -> "<#{t}>"
      t -> ~s(<#{t}> "#{words}")
    end
  end

  # each element's line in the page's source: its own data-line, or that of the element it is in (a kit
  # component's inner parts)
  defp lines(nodes, line, acc) do
    Enum.reduce(nodes, acc, fn
      {tag, attrs, kids}, acc when is_binary(tag) ->
        line = Attrs.attr(attrs, "data-line") || line
        acc = Map.put(acc, Attrs.attr(attrs, "data-mf"), line)
        lines(kids, line, acc)

      _, acc ->
        acc
    end)
  end
end

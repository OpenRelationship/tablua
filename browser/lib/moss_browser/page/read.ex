defmodule Moonflower.Page.Read do
  @moduledoc """
  A page's words as lines (kept as blocks, `blocks/1`), each with its region (the landmark it is in: `:main`, `:nav`, `:banner`, `:footer`,
  `:aside`, `:search`, or `:body` outside them all) and its section (how many headings came before it), and the
  headings as `{section, level, text}`. Hidden things are not read; a list item is a line, an image its alt
  text, and a table row a line whose cells carry their column's header (`Plan: Pro · Price: $12`).
  """
  import Moonflower.Page.Attrs, only: [attr: 2, hidden?: 1, words: 1]
  alias Moonflower.Page.Attrs

  @block ~w(p div section article header footer main nav aside li ul ol dl tr h1 h2 h3 h4 h5 h6 pre blockquote
            form label dt dd figure figcaption fieldset details summary address hr br table)

  def lines(tree) do
    events = walk(tree, %{region: :body, sectioning: false}, [])
    {lines, heads} = to_lines(Enum.reverse(events))
    {blocks(lines), heads}
  end

  @doc """
  Lines of one region and section joined into one binary, `\\n` between them: a page of two thousand short
  paragraphs is then a few binaries off the heap, not two thousand on it. `Page.lines/1` splits them again.
  """
  def blocks(lines) do
    lines
    |> Enum.chunk_by(fn {r, s, _} -> {r, s} end)
    |> Enum.map(fn [{r, s, _} | _] = run -> {r, s, Enum.map_join(run, "\n", &elem(&1, 2))} end)
  end

  # -- the walk: events in reverse ------------------------------------------------------------

  defp walk(nodes, ctx, out) do
    Enum.reduce(nodes, out, fn
      s, out when is_binary(s) ->
        [{:t, ctx.region, s} | out]

      {tag, attrs, kids}, out ->
        cond do
          tag in Attrs.skip() or hidden?(attrs) -> out
          level = Attrs.heading(tag, attrs) -> [{:h, ctx.region, level, words(kids)} | out]
          tag == "table" -> table(kids, ctx, out)
          tag == "img" -> image(attrs, ctx, out)
          tag == "li" -> [:b | walk(kids, ctx, [{:t, ctx.region, "- "}, :b | out])]
          tag in @block -> [:b | walk(kids, Attrs.enter(tag, attrs, ctx), [:b | out])]
          true -> walk(kids, Attrs.enter(tag, attrs, ctx), out)
        end

      _, out ->
        out
    end)
  end

  defp image(attrs, ctx, out) do
    case attr(attrs, "alt") do
      alt when alt in [nil, ""] -> out
      alt -> [{:t, ctx.region, "[image: " <> alt <> "]"} | out]
    end
  end

  # a row per line, each cell with its column's header when the table has a header row
  defp table(kids, ctx, out) do
    rows = rows(kids)

    {head, body} =
      case rows do
        [first | rest] ->
          if Enum.all?(first, &match?({"th", _, _}, &1)),
            do: {Enum.map(first, &cell/1), rest},
            else: {nil, rows}

        [] ->
          {nil, []}
      end

    Enum.reduce(body, [:b | out], fn cells, out ->
      texts = Enum.map(cells, &cell/1)

      line =
        if head,
          do:
            Enum.zip(head ++ List.duplicate("", max(length(texts) - length(head), 0)), texts)
            |> Enum.reject(fn {_, v} -> v == "" end)
            |> Enum.map_join(" · ", fn {h, v} -> if h == "", do: v, else: h <> ": " <> v end),
          else: Enum.join(Enum.reject(texts, &(&1 == "")), " | ")

      [:b, {:t, ctx.region, line}, :b | out]
    end)
  end

  defp rows(nodes) do
    Enum.flat_map(nodes, fn
      {"tr", attrs, kids} ->
        if hidden?(attrs),
          do: [],
          else: [for({t, a, _} = c <- kids, t in ~w(td th), not hidden?(a), do: c)]

      {t, attrs, kids} when t in ~w(thead tbody tfoot) ->
        if hidden?(attrs), do: [], else: rows(kids)

      _ ->
        []
    end)
  end

  defp cell({_, _, kids}), do: words(kids)

  # -- events to lines --------------------------------------------------------------------------

  defp to_lines(events) do
    {lines, heads, cur, section} =
      Enum.reduce(events, {[], [], nil, 0}, fn
        :b, {lines, heads, cur, sec} ->
          {flush(lines, cur, sec), heads, nil, sec}

        {:t, region, s}, {lines, heads, nil, sec} ->
          {lines, heads, {region, [s]}, sec}

        {:t, _, s}, {lines, heads, {region, acc}, sec} ->
          {lines, heads, {region, [acc, s]}, sec}

        {:h, region, level, text}, {lines, heads, cur, sec} ->
          lines = flush(lines, cur, sec)

          if text == "",
            do: {lines, heads, nil, sec},
            else:
              {[{region, sec + 1, String.duplicate("#", level) <> " " <> text} | lines],
               [{sec + 1, level, text} | heads], nil, sec + 1}
      end)

    {Enum.reverse(flush(lines, cur, section)), Enum.reverse(heads)}
  end

  defp flush(lines, nil, _sec), do: lines

  defp flush(lines, {region, acc}, sec) do
    case acc |> IO.iodata_to_binary() |> String.replace(~r/\s+/u, " ") |> String.trim() do
      "" -> lines
      "-" -> lines
      line -> [{region, sec, line} | lines]
    end
  end
end

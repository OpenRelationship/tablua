defmodule MossBrowser.Page.Parts do
  @moduledoc """
  A page read in parts, so an agent pays for what it asks for. `open` shows the map (`summary/1`): the title and
  address, what was not read, the regions and their links, the page's own description and JSON-LD, the headings
  numbered, then the first screen of the main content and its controls. The rest:

      page [n]                part n of the main content, about 2,000 characters each
      page nav|footer|...     the words of a region (banner, nav, aside, search, footer)
      page find <words>       the lines that hold the words, with their sections
      read <n|words>          one section, under its heading
      ui [more|<region>|<words>]   the controls, main content first, fifty at a time; a link repeated once
  """
  alias MossBrowser.Page

  @part 2_000
  @screen 1_500
  @ui 50
  @order [:main, :body, :search, :banner, :nav, :aside, :footer]
  @names %{
    main: "main",
    body: "page",
    search: "search",
    banner: "banner",
    nav: "navigation",
    aside: "aside",
    footer: "footer"
  }
  @asked %{
    "main" => :main,
    "banner" => :banner,
    "header" => :banner,
    "nav" => :nav,
    "navigation" => :nav,
    "aside" => :aside,
    "search" => :search,
    "footer" => :footer
  }

  def region(word), do: Map.get(@asked, word)

  def summary(page) do
    main = main(page)
    parts = main |> chunks(@part) |> length()
    {screen, rest} = take(main, @screen)
    sections = MapSet.new(screen, &elem(&1, 1))

    first =
      page.controls
      |> shown()
      |> Enum.filter(&(&1.region in [:main, :body] and MapSet.member?(sections, &1.section)))
      |> Enum.take(20)

    [
      page.title,
      "\n",
      page.url,
      "\n",
      Enum.map(page.notes, &[&1, "\n"]),
      "\n",
      overview(page, parts),
      "\n",
      about(page),
      headings(page),
      "\n",
      Enum.map_join(screen, "\n", &elem(&1, 2)),
      if(rest != [], do: "\n…(page 2 goes on)", else: ""),
      "\n\n",
      Enum.map(first, &Page.line(page, &1)),
      count(page, length(first))
    ]
    |> IO.iodata_to_binary()
  end

  defp overview(page, parts) do
    regions =
      for r <- @order -- [:main, :body],
          links = Enum.count(page.controls, &(&1.region == r and &1.role == "link")),
          words =
            page.blocks
            |> Enum.filter(&(elem(&1, 0) == r))
            |> Enum.map(&elem(&1, 2))
            |> Enum.join(" ")
            |> String.split()
            |> length(),
          words > 0 or links > 0,
          do: "#{@names[r]}: " <> if(links > 0, do: "#{links} links", else: "#{words} words")

    Enum.join(["#{parts} #{if parts == 1, do: "part", else: "parts"}" | regions], " · ")
  end

  defp about(page) do
    desc = page.data.meta["description"] || page.data.meta["og:description"]
    lines = if(desc, do: [desc], else: []) ++ page.data.ld

    lines =
      if page.data.blobs != [],
        do: lines ++ ["data: #{length(page.data.blobs)} JSON (data lists them)"],
        else: lines

    Enum.map(lines, &[&1, "\n"])
  end

  defp headings(%{headings: []}), do: ""

  defp headings(page) do
    shown = Enum.take(page.headings, 40)
    more = length(page.headings) - length(shown)

    [
      "\nheadings (read <n>):\n",
      shown
      |> Enum.with_index(1)
      |> Enum.map(fn {{_, level, text}, i} ->
        [pad(i), String.duplicate("  ", level - 1), text, "\n"]
      end),
      if(more > 0, do: "   …#{more} more\n", else: "")
    ]
  end

  defp count(page, shown) do
    all = length(shown(page.controls))
    if all > shown, do: "(#{all} controls: ui lists them)\n", else: ""
  end

  # -- parts -------------------------------------------------------------------------------------

  def part(page, n) do
    parts = chunks(main(page), @part)

    case Enum.at(parts, n - 1) do
      nil when parts == [] ->
        "the page has no words\n"

      nil ->
        "the page has #{length(parts)} parts\n"

      lines ->
        "part #{n} of #{length(parts)}\n\n" <> Enum.map_join(lines, "\n", &elem(&1, 2)) <> "\n"
    end
  end

  def of_region(page, region) do
    case Enum.filter(Page.lines(page), &(elem(&1, 0) == region)) do
      [] -> "no #{@names[region]} on the page\n"
      lines -> Enum.map_join(lines, "\n", &elem(&1, 2)) <> "\n"
    end
  end

  def find(page, words) do
    low = words |> String.downcase() |> String.split()
    heads = Map.new(page.headings, fn {s, _, t} -> {s, t} end)

    hits =
      for {_, s, text} <- Page.lines(page),
          down = String.downcase(text),
          Enum.all?(low, &String.contains?(down, &1)),
          do: "[#{Map.get(heads, s, "top")}] " <> String.slice(text, 0, 200)

    case hits do
      [] ->
        "nothing on the page holds \"#{words}\"\n"

      _ ->
        Enum.join(Enum.take(hits, 30), "\n") <>
          if(length(hits) > 30, do: "\n…#{length(hits) - 30} more\n", else: "\n")
    end
  end

  def section(page, said) do
    numbered = Enum.with_index(page.headings, 1)
    low = String.downcase(said)

    found =
      case Integer.parse(said) do
        {i, ""} ->
          Enum.find(numbered, &(elem(&1, 1) == i))

        _ ->
          Enum.find(numbered, fn {{_, _, t}, _} -> String.contains?(String.downcase(t), low) end)
      end

    case found do
      nil ->
        "read: no heading \"#{said}\" (open shows them numbered)\n"

      {{s, level, _}, _} ->
        stop =
          Enum.find_value(page.headings, :end, fn {s2, l2, _} -> s2 > s and l2 <= level and s2 end)

        lines =
          Enum.filter(Page.lines(page), fn {_, s2, _} ->
            s2 >= s and (stop == :end or s2 < stop)
          end)

        {shown, rest} = take(lines, 3 * @part)

        Enum.map_join(shown, "\n", &elem(&1, 2)) <>
          if(rest != [], do: "\n…(the section goes on: page find, or page n)\n", else: "\n")
    end
  end

  # -- controls ----------------------------------------------------------------------------------

  @doc "Controls for `ui`: `{text, next}`, next being where `ui more` starts (nil at the end)."
  def ui(page, filter, from) do
    rank = Map.new(Enum.with_index(@order))

    cs =
      page.controls
      |> shown()
      |> Enum.filter(&match(&1, filter))
      |> Enum.with_index()
      |> Enum.sort_by(fn {c, i} -> {Map.get(rank, c.region, 0), i} end)
      |> Enum.map(&elem(&1, 0))
      |> Enum.uniq_by(fn c -> if c.role == "link", do: {c.name, c.href}, else: c.id end)

    page_of = Enum.slice(cs, from, @ui)
    left = length(cs) - from - length(page_of)

    cond do
      cs == [] ->
        {"no controls#{if filter, do: " match", else: " on the page"}\n", nil}

      left > 0 ->
        {Enum.map_join(page_of, &Page.line(page, &1)) <> "…#{left} more: ui more\n", from + @ui}

      true ->
        {Enum.map_join(page_of, &Page.line(page, &1)), nil}
    end
  end

  defp match(_c, nil), do: true
  defp match(c, region) when is_atom(region), do: c.region == region
  defp match(c, words), do: String.contains?(String.downcase(c.name), String.downcase(words))

  defp shown(cs), do: Enum.reject(cs, &(&1.role == "hidden"))

  # -- helpers -----------------------------------------------------------------------------------

  defp main(page), do: Enum.filter(Page.lines(page), &(elem(&1, 0) in [:main, :body]))

  defp take(lines, max) do
    {a, b, _} =
      Enum.reduce(lines, {[], [], 0}, fn l, {a, b, n} ->
        if n < max or a == [],
          do: {[l | a], b, n + byte_size(elem(l, 2)) + 1},
          else: {a, [l | b], n}
      end)

    {Enum.reverse(a), Enum.reverse(b)}
  end

  defp chunks([], _max), do: []

  defp chunks(lines, max) do
    {a, rest} = take(lines, max)
    [a | chunks(rest, max)]
  end

  defp pad(i), do: String.pad_leading(to_string(i), 3) <> " "
end

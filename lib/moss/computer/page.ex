defmodule Moss.Computer.Page do
  @moduledoc """
  A web page as the computer's browser keeps it: parsed once (`Moss.HTML`, in Elixir, since the page may be
  anyone's), read, and the tree let go. What stays is small (Arock feature browser):

    * `blocks`: its words, as lines `{region, section, text}` (`lines/1`, `Page.Read`), headings as
      `{section, level, text}`;
    * `controls`: its accessibility tree (`Page.Controls`), each with an id the agent names, and `values`,
      what is in each field now;
    * `data`: its meta description, JSON-LD and the JSON it carries (`Page.Data`);
    * `watch`: the page for a person watching, scripts out, gzipped (`Page.Watch`), drawn by `html/1`;
    * `notes`: what the agent should know about how it was read (cut at the cap, a character set not decoded).

      page = Page.new(url, html)
      Page.text(page); page.controls   # [%Control{id: "3", role: "field", name: "Email", ...}]
  """
  alias Moss.Computer.Page.{Controls, Data, Read, Watch}

  defstruct [
    :url,
    :title,
    :watch,
    :refresh,
    blocks: [],
    headings: [],
    controls: [],
    values: %{},
    data: %{meta: %{}, ld: [], blobs: []},
    notes: [],
    answer: false
  ]

  def new(url, html, notes \\ []) do
    tree = Moss.HTML.parse(html)
    {tree, {blocks, headings}, notes} = visible(tree, notes)
    {controls, marked} = Controls.collect(tree)

    %__MODULE__{
      url: url,
      title: title(tree) || url,
      blocks: blocks,
      headings: headings,
      controls: controls,
      values:
        Map.new(for c <- controls, c.role in ["field", "checkbox", "radio"], do: {c.id, c.value}),
      data: Data.read(tree),
      watch: Watch.copy(marked),
      refresh: refresh(tree),
      notes: notes
    }
  end

  # a page that shows almost nothing but hides much more (to reveal with its scripts) is read with it revealed
  defp visible(tree, notes) do
    read = Read.lines(tree)
    shown = count(read)

    if shown < 150 do
      revealed = Moss.Computer.Page.Attrs.reveal(tree)
      again = Read.lines(revealed)

      if count(again) >= max(100, 3 * shown),
        do:
          {revealed, again,
           notes ++ ["(the page hides most of its words until its scripts run; shown anyway)"]},
        else: {tree, read, notes}
    else
      {tree, read, notes}
    end
  end

  defp count({blocks, _}),
    do: Enum.reduce(blocks, 0, fn {_, _, t}, n -> n + length(String.split(t)) end)

  @doc "The page without its watcher's copy or JSON: what history keeps of a page a form answered."
  def slim(page), do: %{page | watch: nil, data: %{page.data | blobs: []}}

  @doc "The page's lines, `{region, section, text}`, from its blocks."
  def lines(page) do
    Enum.flat_map(page.blocks, fn {r, s, text} ->
      for l <- String.split(text, "\n"), do: {r, s, l}
    end)
  end

  @doc "The page's words, headings marked."
  def text(page) do
    page
    |> lines()
    |> Enum.map_join("\n", fn
      {_, _, "#" <> _ = h} -> "\n" <> h
      {_, _, t} -> t
    end)
    |> String.trim()
  end

  @doc "The page's html for a watcher: no scripts, the fields holding their values, links resolved."
  def html(page), do: Watch.html(page)

  @doc "The control named by its id, its name, its form name, or the first whose name holds the words."
  def control(page, said) do
    low = String.downcase(said)
    shown = Enum.reject(page.controls, &(&1.role == "hidden"))

    Enum.find(shown, &(&1.id == said)) || Enum.find(shown, &(String.downcase(&1.name) == low)) ||
      Enum.find(shown, &(&1.field == said)) ||
      Enum.find(shown, &String.contains?(String.downcase(&1.name), low))
  end

  @doc "The controls as lines: `[3] field \"Email\" = ada@example.com (required)`."
  def outline(page) do
    page.controls
    |> Enum.reject(&(&1.role == "hidden"))
    |> Enum.map_join(&line(page, &1))
  end

  @doc "One control as a line, with what is in it, its states and its description."
  def line(page, c) do
    value =
      Map.get(
        page.values,
        c.id,
        if(c.role in ["field", "checkbox", "radio"], do: nil, else: c.value)
      )

    value = if c.role in ["field", "checkbox", "radio"], do: value, else: nil

    shown =
      if c.role == "field" and c.type == "password" and value not in [nil, ""],
        do: "••••",
        else: value

    "[#{c.id}] #{c.role} \"#{c.name}\"" <>
      if(shown not in [nil, ""], do: " = #{shown}", else: "") <>
      if(c.states != [], do: " (#{Enum.join(c.states, ", ")})", else: "") <>
      if(c.desc, do: " — #{c.desc}", else: "") <> "\n"
  end

  defp title(tree) do
    Enum.find_value(nodes(tree), fn
      {"title", _, kids} ->
        kids
        |> Enum.filter(&is_binary/1)
        |> Enum.join()
        |> String.trim()
        |> then(&(&1 != "" && &1))

      _ ->
        nil
    end)
  end

  # where a <meta http-equiv=refresh> of five seconds or less sends the page
  defp refresh(tree) do
    Enum.find_value(nodes(tree), fn
      {"meta", a, _} ->
        with "refresh" <-
               a
               |> Moss.Computer.Page.Attrs.attr("http-equiv")
               |> to_string()
               |> String.downcase(),
             [_, secs, url] <-
               Regex.run(
                 ~r/^\s*(\d+)\s*[;,]\s*url\s*=\s*['"]?([^'"]+)/i,
                 Moss.Computer.Page.Attrs.attr(a, "content") || ""
               ),
             {s, _} when s <= 5 <- Integer.parse(secs),
             do: String.trim(url),
             else: (_ -> nil)

      _ ->
        nil
    end)
  end

  defp nodes(tree),
    do:
      Enum.flat_map(tree, fn
        {_, _, kids} = n -> [n | nodes(kids)]
        _ -> []
      end)
end

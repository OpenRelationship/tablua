defmodule Moonflower.Look do
  @moduledoc """
  A page laid out as a person's browser would lay it out (Arock feature look): Blitz in WebAssembly, in the look
  node (`Moonflower.Look.Node`). `look/3` marks the page's elements (`Moonflower.Look.Mark`), lays it out at a
  width and a theme, and answers which elements are shown and where.

      {:ok, look} = Moonflower.Look.look(node, html, width: 390, base: url)
      Moonflower.Look.shown?(look, "button", "Menu")

  Options: `:width` (1280), `:dark` (false), `:base` (the page's address, for what it links), `:css` (a stylesheet
  laid out with the page, as a `<link>` of it would be, and left out of its tree), `:fuel`
  (#{10_000_000_000}; Wikipedia's longest article needs under 5e9), `:timeout` (ms, 10 s). An error is
  `:too_costly`, `:failed` or `:down`; the caller reads the page without a look then.
  """
  alias Moonflower.Look.{Mark, Node}
  alias Moonflower.Page.Attrs

  defstruct [
    :width,
    :dark,
    :tree,
    shown: %{},
    hidden: MapSet.new(),
    invisible: MapSet.new(),
    elements: 0,
    unmarked: 0,
    ms: {0, 0}
  ]

  def look(node \\ Node, html, opts \\ []) do
    width = Keyword.get(opts, :width, 1280)
    dark = Keyword.get(opts, :dark, false)
    timeout = Keyword.get(opts, :timeout, 10_000)
    {marked, tree} = Mark.mark(html)

    # CSS given beside the page goes in first, so the parser puts it in the head; the page's tree is left as it was
    css = if css = Keyword.get(opts, :css), do: "<style>" <> css <> "</style>", else: ""

    input =
      "#{width} #{if dark, do: 1, else: 0} #{Keyword.get(opts, :base) || ""}\n" <> css <> marked

    fuel = Keyword.get(opts, :fuel, 10_000_000_000)

    with {:ok, peer} <- Node.peer(node),
         {:ok, out} <- call(peer, [input, fuel, timeout], timeout) do
      {:ok, read(out, %__MODULE__{width: width, dark: dark, tree: tree})}
    end
  end

  defp call(peer, args, timeout) do
    :peer.call(peer, Moonflower.Look.Holder, :look, args, timeout + 5_000)
  catch
    :exit, _ -> {:error, :down}
  end

  defp read(out, look) do
    out
    |> String.split("\n", trim: true)
    |> Enum.reduce(look, fn
      "= " <> rest, look ->
        [e, u, p, r] = rest |> String.split() |> Enum.map(&String.to_integer/1)
        %{look | elements: e, unmarked: u, ms: {p, r}}

      line, look ->
        case String.split(line) do
          [n, "-"] -> %{look | hidden: MapSet.put(look.hidden, n)}
          [n, "v"] -> %{look | invisible: MapSet.put(look.invisible, n)}
          [n, "+"] -> %{look | shown: Map.put(look.shown, n, nil)}
          [n, x, y, w, h] -> %{look | shown: Map.put(look.shown, n, box(x, y, w, h))}
          [n, x, y, w, h | more] -> %{look | shown: Map.put(look.shown, n, box(x, y, w, h, more))}
        end
    end)
  end

  defp box(x, y, w, h), do: %{x: int(x), y: int(y), w: int(w), h: int(h)}

  # a module from v0.2.0 on says more of each box: how it is placed and painted (Moonflower.Look.Faults reads it)
  defp box(x, y, w, h, [position, z, color, background, overflow]) do
    Map.merge(box(x, y, w, h), %{
      position: position,
      z: if(z == "a", do: nil, else: int(z)),
      color: rgba(color),
      background: rgba(background),
      clips: overflow == "c"
    })
  end

  defp rgba(hex),
    do: hex |> Base.decode16!(case: :lower) |> :binary.bin_to_list() |> List.to_tuple()

  defp int(s), do: String.to_integer(s)

  @doc "Whether the first element of this tag (holding these words, when given) is shown."
  def shown?(look, tag, words \\ nil) do
    case ids(look.tree, tag, words) do
      [id | _] -> Map.has_key?(look.shown, id)
      [] -> false
    end
  end

  @doc "The boxes of the shown elements of this tag (holding these words, when given)."
  def boxes(look, tag, words \\ nil),
    do: for(id <- ids(look.tree, tag, words), box = look.shown[id], box != nil, do: box)

  @doc """
  The page's tree as the look showed it, its marks taken off: what is not rendered is gone, what is invisible
  keeps only the children that show themselves, and the head is kept whole (the title is in it). An element the
  look did not see (the two parsers differ there) is kept.
  """
  def visible(look), do: keep(look.tree, look, false)

  defp keep(nodes, look, head?) do
    Enum.flat_map(nodes, fn
      {tag, attrs, kids} when is_binary(tag) ->
        id = Attrs.attr(attrs, "data-mf")
        attrs = List.keydelete(attrs, "data-mf", 0)
        head? = head? or tag == "head"

        cond do
          head? ->
            [{tag, attrs, keep(kids, look, true)}]

          MapSet.member?(look.hidden, id) ->
            []

          MapSet.member?(look.invisible, id) ->
            case Enum.filter(keep(kids, look, false), &match?({_, _, _}, &1)) do
              [] -> []
              shown -> [{tag, attrs, shown}]
            end

          true ->
            [{tag, attrs, keep(kids, look, false)}]
        end

      other ->
        [other]
    end)
  end

  defp ids(nodes, tag, words) do
    Enum.flat_map(nodes, fn
      {t, attrs, kids} when is_binary(t) ->
        here =
          if t == tag and (words == nil or String.contains?(Attrs.words(kids), words)),
            do: [Attrs.attr(attrs, "data-mf")],
            else: []

        here ++ ids(kids, tag, words)

      _ ->
        []
    end)
  end
end

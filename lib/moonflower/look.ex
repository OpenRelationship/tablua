defmodule Moonflower.Look do
  @moduledoc """
  A page laid out as a person's browser would lay it out (Arock feature look): Blitz in WebAssembly, in the look
  node (`Moonflower.Look.Node`). `look/3` marks the page's elements (`Moonflower.Look.Mark`), lays it out at a
  width and a theme, and answers which elements are shown and where.

      {:ok, look} = Moonflower.Look.look(node, html, width: 390, base: url)
      Moonflower.Look.shown?(look, "button", "Menu")

  Options: `:width` (1280), `:dark` (false), `:base` (the page's address, for what it links), `:fuel`
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
    elements: 0,
    unmarked: 0,
    ms: {0, 0}
  ]

  def look(node \\ Node, html, opts \\ []) do
    width = Keyword.get(opts, :width, 1280)
    dark = Keyword.get(opts, :dark, false)
    timeout = Keyword.get(opts, :timeout, 10_000)
    {marked, tree} = Mark.mark(html)
    input = "#{width} #{if dark, do: 1, else: 0} #{Keyword.get(opts, :base) || ""}\n" <> marked
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
          [n, x, y, w, h] -> %{look | shown: Map.put(look.shown, n, box(x, y, w, h))}
        end
    end)
  end

  defp box(x, y, w, h), do: %{x: int(x), y: int(y), w: int(w), h: int(h)}
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
    do: for(id <- ids(look.tree, tag, words), box = look.shown[id], do: box)

  @doc "Whether the element with this mark is shown."
  def shown_id?(look, id), do: Map.has_key?(look.shown, id)

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

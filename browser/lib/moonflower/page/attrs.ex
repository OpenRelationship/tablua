defmodule Moonflower.Page.Attrs do
  @moduledoc """
  What the page's readers share about an element: an attribute, whether it is hidden from a reader (aria-hidden,
  `hidden`, an inline `display:none` or `visibility:hidden`), the landmark it opens, and its words as a person
  reads them. `Page.Read` and `Page.Controls` walk the same tree with these, so a section and a region mean the
  same in both.
  """

  # never read: code, styling, and what a reader does not see
  @skip ~w(script style noscript template svg head iframe object embed)
  @landmarks %{
    "nav" => :nav,
    "main" => :main,
    "aside" => :aside,
    "search" => :search
  }
  @roles %{
    "navigation" => :nav,
    "main" => :main,
    "banner" => :banner,
    "contentinfo" => :footer,
    "complementary" => :aside,
    "search" => :search
  }

  def skip, do: @skip

  def attr(attrs, name), do: Enum.find_value(attrs, fn {k, v} -> k == name && v end)

  def hidden?(attrs) do
    attr(attrs, "aria-hidden") == "true" or attr(attrs, "hidden") != nil or
      case attr(attrs, "style") do
        nil -> false
        s -> Regex.match?(~r/(display\s*:\s*none|visibility\s*:\s*hidden)/i, s)
      end
  end

  @doc """
  The tree with nothing hidden: `hidden`, `aria-hidden` and an inline style that hides taken off. For a page
  that hides nearly all its words until its scripts run (X's posts, rendered on the server inside a hidden div).
  """
  def reveal(tree) do
    Enum.map(tree, fn
      {tag, attrs, kids} ->
        attrs =
          Enum.reject(attrs, fn {k, v} ->
            k in ["hidden", "aria-hidden"] or (k == "style" and hidden?([{k, v}]))
          end)

        {tag, attrs, reveal(kids)}

      other ->
        other
    end)
  end

  @doc """
  The region an element opens, given the walk's context (`%{region, sectioning}`): a header or footer is the
  page's banner or footer only outside an article, section, aside or main.
  """
  def region(tag, attrs, ctx) do
    role = attr(attrs, "role")

    cond do
      role && Map.has_key?(@roles, role) -> Map.fetch!(@roles, role)
      Map.has_key?(@landmarks, tag) -> Map.fetch!(@landmarks, tag)
      tag == "header" and not ctx.sectioning -> :banner
      tag == "footer" and not ctx.sectioning -> :footer
      true -> nil
    end
  end

  @doc "The context for an element's children."
  def enter(tag, attrs, ctx) do
    ctx =
      if tag in ~w(article section aside main nav),
        do: %{ctx | sectioning: true},
        else: ctx

    case region(tag, attrs, ctx) do
      nil -> ctx
      r -> %{ctx | region: r}
    end
  end

  @doc "A heading's level, for h1-h6 or role=heading (aria-level, 2 when not given); nil otherwise."
  def heading(tag, attrs) do
    cond do
      tag in ~w(h1 h2 h3 h4 h5 h6) -> String.to_integer(String.slice(tag, 1, 1))
      attr(attrs, "role") == "heading" -> level(attr(attrs, "aria-level"))
      true -> nil
    end
  end

  defp level(nil), do: 2

  defp level(s) do
    case Integer.parse(s) do
      {n, _} when n in 1..6 -> n
      _ -> 2
    end
  end

  @doc "The words a reader hears in these nodes, on one line."
  def words(nodes) do
    nodes |> text([]) |> IO.iodata_to_binary() |> String.replace(~r/\s+/u, " ") |> String.trim()
  end

  defp text(nodes, acc) do
    Enum.reduce(nodes, acc, fn
      s, acc when is_binary(s) ->
        [acc, s]

      {tag, attrs, kids}, acc ->
        cond do
          tag in @skip or hidden?(attrs) -> acc
          tag == "img" -> [acc, " ", attr(attrs, "alt") || "", " "]
          true -> [text(kids, acc), " "]
        end

      _, acc ->
        acc
    end)
  end
end

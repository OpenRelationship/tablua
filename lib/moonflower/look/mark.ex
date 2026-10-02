defmodule Moonflower.Look.Mark do
  @moduledoc """
  The page as moonflower's parser reads it, each element marked `data-mf="<n>"` in document order, so what the look
  says of an element comes back to the element moonflower has. An element the look's parser built and ours did not
  comes back unmarked: the two parsers read the page differently there.
  """
  alias Moonflower.HTML

  @doc "`{marked_html, tree}`: the HTML to look at, and the marked tree to read its answer against."
  def mark(html) do
    {tree, _} = number(HTML.parse(html), 0)
    {HTML.to_html(tree), tree}
  end

  defp number(nodes, n) do
    Enum.map_reduce(nodes, n, fn
      {tag, attrs, kids}, n when is_binary(tag) ->
        {kids, next} = number(kids, n + 1)
        {{tag, [{"data-mf", Integer.to_string(n)} | attrs], kids}, next}

      other, n ->
        {other, n}
    end)
  end
end

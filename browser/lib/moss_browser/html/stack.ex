defmodule MossBrowser.HTML.Stack do
  @moduledoc """
  The tree builder's stack of open elements (HTML standard §13.2.4.3) and the tree it builds. Each open element
  holds its children, newest first; an element joins its parent when it is popped, so a node set aside by foster
  parenting (§13.2.6.1) lands before its table, which is not yet in its own parent.

  A finished node is `{name, attrs, children}`, a text is a binary and a comment `{:comment, text}`, the shape
  `MossBrowser.HTML.parse/1` returns.
  """

  @special_html ~w(address applet area article aside base basefont bgsound blockquote body br button caption center
                   col colgroup dd details dir div dl dt embed fieldset figcaption figure footer form frame frameset
                   h1 h2 h3 h4 h5 h6 head header hgroup hr html iframe img input keygen li link listing main marquee
                   menu meta nav noembed noframes noscript object ol p param plaintext pre script search section
                   select source style summary table tbody td template textarea tfoot th thead title tr track ul wbr
                   xmp)
  @mathml_text ~w(mi mo mn ms mtext)
  @svg_html ~w(foreignobject desc title)
  @scope_html ~w(applet caption html table td th marquee object template)
  @table_ctx ~w(table tbody thead tfoot tr)

  def entry(name, ns, attrs, foster? \\ false),
    do: %{n: name, ns: ns, a: attrs, k: [], f: foster?, d: 0, p: false}

  # -- what an element is --------------------------------------------------------------------------

  def special?(%{ns: :html, n: n}), do: n in @special_html
  def special?(%{ns: :math, n: n}), do: n in @mathml_text or n == "annotation-xml"
  def special?(%{ns: :svg, n: n}), do: n in @svg_html

  def mathml_text?(%{ns: :math, n: n}), do: n in @mathml_text
  def mathml_text?(_), do: false

  def html_point?(%{ns: :svg, n: n}), do: n in @svg_html

  def html_point?(%{ns: :math, n: "annotation-xml", a: a}) do
    case List.keyfind(a, "encoding", 0) do
      {_, enc} -> MossBrowser.HTML.Tokenizer.lower(enc) in ["text/html", "application/xhtml+xml"]
      nil -> false
    end
  end

  def html_point?(_), do: false

  def table_ctx?(%{ns: :html, n: n}), do: n in @table_ctx
  def table_ctx?(_), do: false

  def html?(%{ns: :html, n: n}, names), do: n in names
  def html?(_, _), do: false

  # -- scope (§13.2.4.2) ---------------------------------------------------------------------------

  @doc "Is an HTML element named in `names` open in the given kind of scope?"
  def in_scope?(stack, names, kind \\ :default) do
    Enum.reduce_while(stack, false, fn e, _ ->
      cond do
        html?(e, names) -> {:halt, true}
        boundary?(e, kind) -> {:halt, false}
        true -> {:cont, false}
      end
    end)
  end

  defp boundary?(e, :table), do: html?(e, ~w(html table template))
  defp boundary?(e, :list), do: html?(e, ~w(ol ul)) or boundary?(e, :default)
  defp boundary?(e, :button), do: html?(e, ["button"]) or boundary?(e, :default)

  defp boundary?(e, :default),
    do:
      html?(e, @scope_html) or mathml_text?(e) or (e.ns == :math and e.n == "annotation-xml") or
        (e.ns == :svg and e.n in @svg_html)

  # -- building ------------------------------------------------------------------------------------

  # As in Blink, elements nest at most 512 deep; past that the current one is closed first, so every walk of the
  # stack is bounded and a page of endless unclosed tags costs time in proportion to its length.
  @deepest 512

  def push([%{d: d} | _] = stack, e) when d >= @deepest, do: push(pop(stack), e)

  def push([top | _] = stack, e) do
    p? = html?(e, ["p"]) or (top.p and not boundary?(e, :button))
    [%{e | d: top.d + 1, p: p?} | stack]
  end

  @doc "Is a `p` open in button scope? Kept on each element as it is pushed, since every block start asks."
  def p_in_scope?([top | _]), do: top.p

  @doc "Puts a finished node in the current element, or before the table when it is foster parented."
  def append(stack, node, foster? \\ false)
  def append(stack, node, true), do: foster(stack, node)
  def append([top | rest], node, false), do: [%{top | k: add(top.k, node)} | rest]

  def text(stack, "", _foster?), do: stack
  def text(stack, t, foster?), do: append(stack, {:t, t}, foster?)

  def pop([top | rest]), do: append(rest, finish(top), top.f)

  @doc "Pops until an HTML element of that name has been popped."
  def pop_to(stack, name) when is_binary(name), do: pop_to(stack, [name])

  def pop_to([top | _] = stack, names) do
    if html?(top, names), do: pop(stack), else: pop_to(pop(stack), names)
  end

  @doc "Pops the top `n` elements."
  def pop_n(stack, 0), do: stack
  def pop_n(stack, n), do: pop_n(pop(stack), n - 1)

  @doc "Pops while the current element is not an HTML element named in `names`."
  def clear_to([top | _] = stack, names) do
    if html?(top, ["html", "template" | names]), do: stack, else: clear_to(pop(stack), names)
  end

  def finish(%{n: n, a: a, k: k}), do: {n, a, Enum.reduce(k, [], &done/2)}

  defp done({:t, io}, acc), do: [IO.iodata_to_binary(io) | acc]
  defp done(node, acc), do: [node | acc]

  # texts side by side are one text
  defp add([{:t, io} | k], {:t, t}), do: [{:t, [io | t]} | k]
  defp add(k, node), do: [node | k]

  defp foster(stack, node) do
    case Enum.split_while(stack, &(not html?(&1, ["table"]))) do
      {above, [table, parent | below]} ->
        above ++ [table, %{parent | k: add(parent.k, node)} | below]

      _ ->
        append(stack, node, false)
    end
  end

  @doc "Adds attributes an element does not yet have (a second `<html>` or `<body>` tag)."
  def merge(stack, name, attrs) do
    Enum.map(stack, fn
      %{ns: :html, n: ^name} = e ->
        have = MapSet.new(e.a, &elem(&1, 0))
        %{e | a: e.a ++ Enum.reject(attrs, fn {k, _} -> MapSet.member?(have, k) end)}

      e ->
        e
    end)
  end
end

defmodule MossBrowser.HTML do
  @moduledoc """
  HTML read and written in Elixir alone, so no page an agent writes or its browser fetches reaches native code
  (Arock PROJECT.md §14.7 item 9: the BEAM is the microVM and Lua the boundary).

      [{"html", attrs, [head, body]}] = MossBrowser.HTML.parse(page)
      MossBrowser.HTML.to_html(nodes)

  `parse/1` follows the HTML standard's tokenizer (`MossBrowser.HTML.Tokenizer`) and enough of its tree construction
  (`MossBrowser.HTML.Tree`, `MossBrowser.HTML.Body`) to read real pages. A node is `{name, attrs, children}`, a text a binary,
  a comment `{:comment, text}`; names are lower case, attributes `{name, value}` in the order written.

  `to_html/1` writes a tree back so that every `<` in what it writes begins a tag it means, however a browser
  reads the rest: every text and attribute value escaped, comments left out, the text of a raw-text element
  (style, script ...) written as is only if it holds no `<`, and an element or attribute whose name could not
  have come from a tag unwrapped or left out.
  """

  alias MossBrowser.HTML.{Tokenizer, Tree}

  @void ~w(area base basefont bgsound br col embed frame hr img input keygen link meta param source track wbr)
  @raw ~w(style script xmp iframe noembed noframes noscript plaintext)

  @doc "The document's tree."
  def parse(html) when is_binary(html), do: Tree.parse(html)

  @doc "The nodes as HTML."
  def to_html(nodes) when is_list(nodes),
    do: nodes |> Enum.map(&node(&1, :html, nil)) |> IO.iodata_to_binary()

  # `ns` is the namespace a browser reading the output is in (svg and math change how a tag is read: there a
  # style is not raw text and a textarea keeps its first newline); `raw` names the raw-text element a text is in
  defp node(text, _ns, nil) when is_binary(text), do: escape(text)
  defp node(text, _ns, raw) when is_binary(text), do: raw(text, raw)

  defp node({name, attrs, kids}, ns, _raw) when is_binary(name) do
    if tag_name?(name) do
      open = ["<", name, Enum.map(attrs, &attr/1)]

      if name in @void do
        [open, "/>"]
      else
        html? = ns == :html
        raw = if html? and name in @raw, do: name

        lf =
          if html? and name in ~w(pre textarea listing) and match?(["\n" <> _ | _], kids),
            do: "\n",
            else: ""

        inner = inner(ns, name, attrs)
        [open, ">", lf, Enum.map(kids, &node(&1, inner, raw)), "</", name, ">"]
      end
    else
      Enum.map(kids, &node(&1, ns, nil))
    end
  end

  defp node(_comment, _ns, _raw), do: []

  defp inner(:html, "svg", _), do: :svg
  defp inner(:html, "math", _), do: :math
  defp inner(:svg, n, _) when n in ~w(foreignobject desc title), do: :html
  defp inner(:math, n, _) when n in ~w(mi mo mn ms mtext), do: :html

  defp inner(:math, "annotation-xml", attrs) do
    case List.keyfind(attrs, "encoding", 0) do
      {_, enc} ->
        if Tokenizer.lower(enc) in ["text/html", "application/xhtml+xml"], do: :html, else: :math

      nil ->
        :math
    end
  end

  defp inner(ns, _, _), do: ns

  defp attr({k, v}), do: if(attr_name?(k), do: [" ", k, "=\"", escape_attr(v), "\""], else: [])

  # A raw-text element's text cannot be escaped, and a browser may not read it as raw text at all (an element
  # it ignores, in a select say), so it is written only if it holds no `<`: then however it is read, it is text.
  defp raw(text, _parent), do: if(:binary.match(text, "<") == :nomatch, do: text, else: "")

  defp tag_name?(<<c, rest::binary>>) when c in ?a..?z, do: tag_rest?(rest)
  defp tag_name?(_), do: false

  defp tag_rest?(<<c, rest::binary>>) when c in ?a..?z or c in ?0..?9 or c == ?-,
    do: tag_rest?(rest)

  defp tag_rest?(<<>>), do: true
  defp tag_rest?(_), do: false

  # anything a tag could have read as one name: no space, quote, `<`, `>`, `/`, `=` or control
  defp attr_name?(""), do: false
  defp attr_name?(k), do: attr_rest?(k)

  defp attr_rest?(<<c, _::binary>>) when c <= 0x20 or c in [?", ?', ?<, ?>, ?/, ?=, 0x7F],
    do: false

  defp attr_rest?(<<_, rest::binary>>), do: attr_rest?(rest)
  defp attr_rest?(<<>>), do: true

  @doc "Text escaped for HTML: `&`, `<` and `>`."
  def escape(text) do
    if :binary.match(text, Tokenizer.pat(:escape)) == :nomatch,
      do: text,
      else: text |> rep("&", "&amp;") |> rep("<", "&lt;") |> rep(">", "&gt;")
  end

  @doc "An attribute's value escaped for a double-quoted attribute: `&`, `\"`, `<` and `>`."
  def escape_attr(v) do
    if :binary.match(v, Tokenizer.pat(:escape_attr)) == :nomatch,
      do: v,
      else: v |> escape() |> rep("\"", "&quot;")
  end

  defp rep(s, a, b), do: :binary.replace(s, a, b, [:global])
end

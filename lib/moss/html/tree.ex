defmodule Moss.HTML.Tree do
  @moduledoc """
  The HTML standard's tree construction (§13.2.6), as much of it as reading and cleaning pages needs: the
  document's html, head and body made whether written or not, head content kept in the head, foreign content
  (svg and math, with their integration points and the HTML tags that break out of them), and the body's rules
  in `Moss.HTML.Body`.

  Left out on purpose: quirks mode, the adoption agency's re-parenting of misnested formatting elements, and the
  rebuilding of formatting elements after a block closes them. Pages read the same; a tree may nest a little
  differently from a browser's, and the cleaner's safety never rests on the two agreeing.
  """

  alias Moss.HTML.{Body, Stack, Tokenizer}

  @head_void ~w(base basefont bgsound link meta)
  @head_raw ~w(title noscript noframes style script template)
  @breakout ~w(b big blockquote body br center code dd div dl dt em embed h1 h2 h3 h4 h5 h6 head hr i img li
               listing menu meta nobr ol p pre ruby s small span strong strike sub sup table tt u ul var)
  @rcdata ~w(title textarea)
  @rawtext ~w(style xmp iframe noembed noframes noscript)

  @doc "The document's tree: `[{\"html\", attrs, [head, body]}]`."
  def parse(html) do
    st = %{
      stack: [Stack.entry("html", :html, [])],
      phase: :before_head,
      form: false,
      skip_lf: false,
      ts: Tokenizer.new()
    }

    loop(Tokenizer.prepare(html), st)
  end

  defp loop(input, st) do
    ts = %{st.ts | foreign: hd(st.stack).ns != :html}

    case Tokenizer.next(input, ts) do
      :eof -> done(st)
      {tok, rest, ts} -> loop(rest, step(tok, %{st | ts: ts}))
    end
  end

  defp step(tok, %{skip_lf: true} = st) do
    st = %{st | skip_lf: false}

    case tok do
      {:text, "\n"} -> st
      {:text, "\n" <> t} -> step(tok_text(t), st)
      _ -> step(tok, st)
    end
  end

  defp step(tok, st), do: process(tok, st)

  defp tok_text(t), do: {:text, t}

  defp done(st) do
    st =
      case st.phase do
        :before_head -> st |> open("head", []) |> close_head()
        :in_head -> close_head(st)
        _ -> st
      end

    st = if st.phase == :after_head, do: open(%{st | phase: :in_body}, "body", []), else: st
    [Stack.finish(hd(Stack.pop_n(st.stack, length(st.stack) - 1)))]
  end

  # -- dispatch ------------------------------------------------------------------------------------

  @doc "Handles a token where the document is now; the body's rules call it back to reprocess one."
  def process(tok, %{phase: :before_head} = st), do: before_head(tok, st)
  def process(tok, %{phase: :in_head} = st), do: in_head(tok, st)
  def process(tok, %{phase: :after_head} = st), do: after_head(tok, st)

  def process(tok, st) do
    cur = hd(st.stack)

    html? =
      cur.ns == :html or
        (Stack.mathml_text?(cur) and
           (match?({:text, _}, tok) or
              match?({:start, n, _, _} when n not in ~w(mglyph malignmark), tok))) or
        (cur.ns == :math and cur.n == "annotation-xml" and match?({:start, "svg", _, _}, tok)) or
        (Stack.html_point?(cur) and (match?({:start, _, _, _}, tok) or match?({:text, _}, tok)))

    if html?, do: Body.step(tok, st), else: foreign(tok, st)
  end

  # -- before and in the head ----------------------------------------------------------------------

  defp before_head({:text, t}, st) do
    case trim_ws(t) do
      "" -> st
      rest -> st |> open("head", []) |> close_head() |> process_again({:text, rest})
    end
  end

  defp before_head({:start, "html", a, _}, st),
    do: %{st | stack: Stack.merge(st.stack, "html", a)}

  defp before_head({:start, "head", a, _}, st), do: %{open(st, "head", a) | phase: :in_head}

  defp before_head({:start, _, _, _} = tok, st),
    do: process_again(%{open(st, "head", []) | phase: :in_head}, tok)

  defp before_head({:end, n} = tok, st) when n in ~w(head body html br),
    do: process_again(%{open(st, "head", []) | phase: :in_head}, tok)

  defp before_head(_, st), do: st

  # a template, or a raw element's text, in the head is handled where it is
  defp in_head(tok, %{stack: [%{n: n} | _]} = st) when n not in ["head"] do
    case tok do
      {:end, ^n} -> %{st | stack: Stack.pop(st.stack)}
      _ -> Body.step(tok, st)
    end
  end

  defp in_head({:text, t}, st) do
    rest = trim_ws(t)
    lead = binary_part(t, 0, byte_size(t) - byte_size(rest))
    st = %{st | stack: Stack.text(st.stack, lead, false)}
    if rest == "", do: st, else: st |> close_head() |> process_again({:text, rest})
  end

  defp in_head({:comment, c}, st), do: %{st | stack: Stack.append(st.stack, {:comment, c})}
  defp in_head({:start, "html", a, _}, st), do: %{st | stack: Stack.merge(st.stack, "html", a)}
  defp in_head({:start, n, a, _}, st) when n in @head_void, do: void(st, n, a)
  defp in_head({:start, n, a, _}, st) when n in @head_raw, do: open(st, n, a)
  defp in_head({:start, "head", _, _}, st), do: st
  defp in_head({:end, "head"}, st), do: close_head(st)

  defp in_head({:end, n} = tok, st) when n in ~w(body html br),
    do: st |> close_head() |> process_again(tok)

  defp in_head({:end, _}, st), do: st
  defp in_head({:doctype, _}, st), do: st
  defp in_head(tok, st), do: st |> close_head() |> process_again(tok)

  defp close_head(st), do: %{st | stack: Stack.pop_to(st.stack, "head"), phase: :after_head}

  defp after_head({:text, t}, st) do
    case trim_ws(t) do
      "" -> st
      rest -> st |> body() |> process_again({:text, rest})
    end
  end

  defp after_head({:start, "html", a, _}, st), do: %{st | stack: Stack.merge(st.stack, "html", a)}
  defp after_head({:start, "body", a, _}, st), do: %{open(st, "body", a) | phase: :in_body}

  defp after_head({:start, n, _, _} = tok, st) when n in @head_void or n in @head_raw,
    do: st |> reopen_head() |> process_again(tok)

  defp after_head({:start, "head", _, _}, st), do: st
  defp after_head({:start, _, _, _} = tok, st), do: st |> body() |> process_again(tok)

  defp after_head({:end, n} = tok, st) when n in ~w(body html br),
    do: st |> body() |> process_again(tok)

  defp after_head(_, st), do: st

  defp body(st), do: %{open(st, "body", []) | phase: :in_body}

  # a head tag after the head: back into the head it goes (§13.2.6.4.6)
  defp reopen_head(%{stack: [html]} = st) do
    {[{"head", a, kids}], others} = Enum.split_with(html.k, &match?({"head", _, _}, &1))
    head = %{Stack.entry("head", :html, a) | k: Enum.reverse(kids)}
    %{st | stack: [head, %{html | k: others}], phase: :in_head}
  end

  defp process_again(st, tok), do: process(tok, st)

  defp trim_ws(t), do: String.replace(t, ~r/\A[ \t\n\f]+/, "")

  # -- foreign content (§13.2.6.5) -----------------------------------------------------------------

  defp foreign({:text, t}, st),
    do: %{st | stack: Stack.text(st.stack, String.replace(t, <<0>>, "�"), false)}

  defp foreign({:comment, c}, st), do: %{st | stack: Stack.append(st.stack, {:comment, c})}

  defp foreign({:start, n, _, _} = tok, st) when n in @breakout,
    do: Body.step(tok, out_of_foreign(st))

  defp foreign({:start, "font", a, _} = tok, st) do
    if Enum.any?(a, fn {k, _} -> k in ~w(color face size) end),
      do: Body.step(tok, out_of_foreign(st)),
      else: foreign_open(st, "font", a, elem(tok, 3))
  end

  defp foreign({:start, n, a, sc}, st), do: foreign_open(st, n, a, sc)

  defp foreign({:end, n} = tok, st) when n in ["br", "p"], do: Body.step(tok, out_of_foreign(st))

  defp foreign({:end, n} = tok, st) do
    {foreign, _} = Enum.split_while(st.stack, &(&1.ns != :html))

    case Enum.find_index(foreign, &(&1.n == n)) do
      nil -> Body.step(tok, st)
      i -> %{st | stack: Stack.pop_n(st.stack, i + 1)}
    end
  end

  defp foreign(_, st), do: st

  defp foreign_open(st, n, a, sc) do
    ns = hd(st.stack).ns
    stack = Stack.push(st.stack, Stack.entry(n, ns, a))
    %{st | stack: if(sc, do: Stack.pop(stack), else: stack)}
  end

  defp out_of_foreign(%{stack: [cur | _] = stack} = st) do
    if cur.ns == :html or Stack.mathml_text?(cur) or Stack.html_point?(cur),
      do: st,
      else: out_of_foreign(%{st | stack: Stack.pop(stack)})
  end

  # -- opening elements, shared with the body's rules -----------------------------------------------

  @doc "Opens an HTML element, foster parented if asked, and sets how the text after it is read."
  def open(st, n, a, foster? \\ false) do
    ts =
      cond do
        n in @rcdata -> %{st.ts | mode: :rcdata, last: n}
        n in @rawtext -> %{st.ts | mode: :rawtext, last: n}
        n == "script" -> %{st.ts | mode: :script, last: n}
        n == "plaintext" -> %{st.ts | mode: :plaintext, last: n}
        true -> st.ts
      end

    %{st | stack: Stack.push(st.stack, Stack.entry(n, :html, a, foster?)), ts: ts}
  end

  @doc "Inserts an element that has no children (br, img, input, meta ...)."
  def void(st, n, a, foster? \\ false),
    do: %{st | stack: Stack.append(st.stack, {n, a, []}, foster?)}

  @doc "Opens an svg or math element, the root of foreign content."
  def foreign_root(st, n, a, sc) do
    e = Stack.entry(n, if(n == "svg", do: :svg, else: :math), a, Stack.table_ctx?(hd(st.stack)))
    stack = Stack.push(st.stack, e)
    %{st | stack: if(sc, do: Stack.pop(stack), else: stack)}
  end
end

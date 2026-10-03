defmodule MossBrowser.HTML.Body do
  @moduledoc """
  The rules for the body (HTML standard §13.2.6.4.7) and its tables (§13.2.6.4.9-15): the end tags a start tag
  implies (a `<p>` closed by a block, an `<li>` by the next, cells, rows and row groups by each other), rows and
  row groups implied around cells, foster parenting of what a table cannot hold, the one-form rule, and end tags
  that match nothing ignored.
  """

  alias MossBrowser.HTML.{Stack, Tree}

  @closes_p ~w(address article aside blockquote center details dialog dir div dl fieldset figcaption figure footer
               header hgroup main menu nav ol p search section summary ul)
  @headings ~w(h1 h2 h3 h4 h5 h6)
  @void ~w(area br embed img keygen wbr input param source track base basefont bgsound link meta)
  @opens_raw ~w(title style noframes noscript iframe noembed script template)
  @parts ~w(caption col colgroup tbody td tfoot th thead tr)
  @end_scoped ~w(address article aside blockquote button center details dialog dir div dl fieldset figcaption
                 figure footer header hgroup listing main menu nav ol pre search section summary ul applet marquee
                 object select)
  @markers ~w(td th caption applet marquee object template html)

  def step({:text, t}, st), do: text(no_nul(t), st)
  def step({:comment, c}, st), do: %{st | stack: Stack.append(st.stack, {:comment, c})}
  def step({:start, n, a, sc}, st), do: start(n, a, sc, st)
  def step({:end, n}, st), do: end_tag(n, st)
  def step(_, st), do: st

  # -- text ----------------------------------------------------------------------------------------

  defp text("", st), do: st

  defp text(t, %{stack: [cur | _]} = st) do
    cond do
      Stack.table_ctx?(cur) -> %{st | stack: Stack.text(st.stack, t, not blank?(t))}
      Stack.html?(cur, ["colgroup"]) and not blank?(t) -> again(pop(st), {:text, t})
      true -> %{st | stack: Stack.text(st.stack, t, false)}
    end
  end

  defp no_nul(t),
    do:
      if(:binary.match(t, <<0>>) == :nomatch,
        do: t,
        else: :binary.replace(t, <<0>>, "", [:global])
      )

  defp blank?(<<c, rest::binary>>) when c in [?\s, ?\t, ?\n, ?\f], do: blank?(rest)
  defp blank?(<<>>), do: true
  defp blank?(_), do: false

  # -- start tags ----------------------------------------------------------------------------------

  defp start(n, a, sc, %{stack: [cur | _]} = st) do
    cond do
      Stack.html?(cur, ["colgroup"]) and n not in ["col", "template"] ->
        again(pop(st), {:start, n, a, sc})

      n in @parts ->
        part(n, a, sc, st)

      n == "table" and Stack.table_ctx?(cur) ->
        again(pop_to(st, "table"), {:start, n, a, sc})

      Stack.table_ctx?(cur) and n in ~w(style script template) ->
        Tree.open(st, n, a)

      Stack.table_ctx?(cur) and n == "input" and hidden?(a) ->
        Tree.void(st, n, a)

      Stack.table_ctx?(cur) and n == "form" ->
        if st.form, do: st, else: %{Tree.void(st, n, a) | form: true}

      true ->
        body_start(n, a, sc, st)
    end
  end

  defp hidden?(a),
    do: match?({_, v} when v in ["hidden", "HIDDEN", "Hidden"], List.keyfind(a, "type", 0))

  defp body_start(n, a, sc, st) do
    cond do
      n in ["html", "body"] -> %{st | stack: Stack.merge(st.stack, n, a)}
      n == "hr" -> st |> close_p() |> put_void(n, a)
      n == "image" -> put_void(st, "img", a)
      n in @void -> put_void(st, n, a)
      n in @opens_raw -> put(st, n, a)
      n in @closes_p or n in ~w(plaintext xmp table) -> st |> close_p() |> put(n, a)
      n in @headings -> st |> close_p() |> close_heading() |> put(n, a)
      n in ~w(pre listing) -> %{put(close_p(st), n, a) | skip_lf: true}
      n == "textarea" -> %{put(st, n, a) | skip_lf: true}
      n == "form" -> if st.form, do: st, else: %{put(close_p(st), n, a) | form: true}
      n == "li" -> st |> close_item(["li"]) |> close_p() |> put(n, a)
      n in ~w(dd dt) -> st |> close_item(~w(dd dt)) |> close_p() |> put(n, a)
      n in ~w(button nobr) -> st |> close_if_open(n) |> put(n, a)
      n == "select" and Stack.in_scope?(st.stack, ["select"]) -> pop_to(st, "select")
      n == "a" -> st |> close_a() |> put(n, a)
      n in ~w(option optgroup) -> st |> pop_if("option") |> put(n, a)
      n in ~w(svg math) -> Tree.foreign_root(st, n, a, sc)
      n in ~w(frame frameset head) -> st
      true -> put(st, n, a)
    end
  end

  # a table part: in a cell or caption it closes that first; outside a table it is ignored
  defp part(n, a, sc, st) do
    tok = {:start, n, a, sc}

    cond do
      Stack.in_scope?(st.stack, ~w(td th), :table) -> again(pop_to(st, ~w(td th)), tok)
      Stack.in_scope?(st.stack, ["caption"], :table) -> again(pop_to(st, "caption"), tok)
      Stack.in_scope?(st.stack, ["table"], :table) -> in_table(n, a, st)
      true -> st
    end
  end

  defp in_table(n, a, st) do
    cur = hd(st.stack)

    case n do
      "col" ->
        st =
          if Stack.html?(cur, ["colgroup"]),
            do: st,
            else: st |> clear_to([]) |> Tree.open("colgroup", [])

        Tree.void(st, "col", a)

      n when n in ~w(caption colgroup tbody thead tfoot) ->
        st |> clear_to([]) |> Tree.open(n, a)

      "tr" ->
        st |> clear_to(~w(tbody thead tfoot)) |> group() |> Tree.open(n, a)

      _cell ->
        st = clear_to(st, ~w(tr tbody thead tfoot))

        st =
          if Stack.html?(hd(st.stack), ["tr"]), do: st, else: st |> group() |> Tree.open("tr", [])

        Tree.open(st, n, a)
    end
  end

  defp group(st),
    do: if(Stack.html?(hd(st.stack), ["table"]), do: Tree.open(st, "tbody", []), else: st)

  defp clear_to(st, names), do: %{st | stack: Stack.clear_to(st.stack, ["table" | names])}

  # -- end tags ------------------------------------------------------------------------------------

  defp end_tag(n, st) do
    cond do
      n in ~w(body html col) ->
        st

      n == "colgroup" ->
        if Stack.html?(hd(st.stack), ["colgroup"]), do: pop(st), else: st

      n in @end_scoped ->
        close_if_open(st, n)

      n == "form" ->
        close_if_open(%{st | form: false}, n)

      n == "p" ->
        st |> ensure_p() |> pop_to("p")

      n == "li" ->
        if Stack.in_scope?(st.stack, ["li"], :list), do: pop_to(st, "li"), else: st

      n in ~w(dd dt) ->
        close_if_open(st, n)

      n in @headings ->
        if Stack.in_scope?(st.stack, @headings), do: pop_to(st, @headings), else: st

      n == "br" ->
        Tree.void(st, "br", [], Stack.table_ctx?(hd(st.stack)))

      n in ~w(table tbody tfoot thead tr td th caption) ->
        table_end(n, st)

      n == "template" ->
        if Enum.any?(st.stack, &Stack.html?(&1, [n])), do: pop_to(st, n), else: st

      true ->
        any_other(n, st)
    end
  end

  defp table_end(n, st),
    do: if(Stack.in_scope?(st.stack, [n], :table), do: pop_to(st, n), else: st)

  defp ensure_p(st) do
    if Stack.p_in_scope?(st.stack),
      do: st,
      else: Tree.open(st, "p", [], Stack.table_ctx?(hd(st.stack)))
  end

  # §13.2.6.4.7, "any other end tag": the nearest open element of that name, unless a special one is in the way
  defp any_other(n, st), do: any_other(st.stack, n, 1, st)

  defp any_other([e | rest], n, depth, st) do
    cond do
      Stack.html?(e, [n]) -> %{st | stack: Stack.pop_n(st.stack, depth)}
      Stack.special?(e) -> st
      true -> any_other(rest, n, depth + 1, st)
    end
  end

  defp any_other([], _n, _depth, st), do: st

  # -- helpers -------------------------------------------------------------------------------------

  defp close_p(st), do: if(Stack.p_in_scope?(st.stack), do: pop_to(st, "p"), else: st)

  defp close_heading(%{stack: [cur | _]} = st),
    do: if(Stack.html?(cur, @headings), do: pop(st), else: st)

  defp close_if_open(st, n), do: if(Stack.in_scope?(st.stack, [n]), do: pop_to(st, n), else: st)

  defp pop_if(%{stack: [cur | _]} = st, n), do: if(Stack.html?(cur, [n]), do: pop(st), else: st)

  # an li closes the li it is in, unless a special element other than address, div or p lies between
  defp close_item(st, names) do
    Enum.reduce_while(st.stack, st, fn e, st ->
      cond do
        Stack.html?(e, names) -> {:halt, pop_to(st, e.n)}
        Stack.special?(e) and not Stack.html?(e, ~w(address div p)) -> {:halt, st}
        true -> {:cont, st}
      end
    end)
  end

  # a link in a link closes the first (the adoption agency's simple case)
  defp close_a(st) do
    Enum.reduce_while(st.stack, st, fn e, st ->
      cond do
        Stack.html?(e, ["a"]) -> {:halt, pop_to(st, "a")}
        Stack.html?(e, @markers) -> {:halt, st}
        true -> {:cont, st}
      end
    end)
  end

  # an element goes where the current node is when it is inserted; before the table if that is a table's
  defp put(st, n, a), do: Tree.open(st, n, a, Stack.table_ctx?(hd(st.stack)))
  defp put_void(st, n, a), do: Tree.void(st, n, a, Stack.table_ctx?(hd(st.stack)))

  defp pop(st), do: %{st | stack: Stack.pop(st.stack)}
  defp pop_to(st, names), do: %{st | stack: Stack.pop_to(st.stack, names)}
  defp again(st, tok), do: Tree.process(tok, st)
end

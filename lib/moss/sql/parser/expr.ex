defmodule Moss.Sql.Parser.Expr do
  @moduledoc """
  Expressions, by SQLite's precedence (lowest first): OR, AND, NOT, the
  equality family (`=`, `!=`, IS, IN, LIKE, GLOB, BETWEEN, ISNULL, NOTNULL),
  `< <= > >=`, `& | << >>`, `+ -`, `* / %`, `||`, then unary `- + ~` and
  COLLATE. Nesting is held to #{100} levels.

  The tree: `{:lit, v}`, `{:param, n}`, `{:col, table | nil, name}`,
  `{:bin, op, a, b}`, `{:and, a, b}`, `{:or, a, b}`, `{:not, e}`,
  `{:neg, e}`, `{:bitnot, e}`, `{:is, a, b, negated}`, `{:between, e, lo, hi, negated}`,
  `{:in, e, {:list, es} | {:select, s}, negated}`, `{:like, kind, e, pattern, escape, negated}`,
  `{:case, base, [{when, then}], else}`, `{:cast, e, type}`, `{:collate, e, name}`,
  `{:fn, name, args | :star, distinct}`, `{:subquery, s}`, `{:exists, s}`, `{:now, kind}`.
  """
  import Moss.Sql.Parser.Tokens
  alias Moss.Sql.Parser.Select

  # SQLite's limit on an expression's height (SQLITE_MAX_EXPR_DEPTH), counted as it counts it: a node is one
  # more than its tallest child and parentheses add nothing; and a bound on the parser's own nesting.
  @max_depth 1000
  @max_nesting 2000

  def parse(ts) do
    depth = Process.get(:sql_depth, 0) + 1

    if depth > @max_nesting,
      do: fail("Expression tree is too large (maximum depth #{@max_depth})")

    Process.put(:sql_depth, depth)
    {e, rest} = parse_or(ts)
    Process.put(:sql_depth, depth - 1)

    if depth == 1 and height(e) > @max_depth,
      do: fail("Expression tree is too large (maximum depth #{@max_depth})")

    {e, rest}
  end

  # an expression's height, subqueries included; its leaves are the tuples with no expression inside
  defp height({:lit, _}), do: 1

  defp height(t) when is_tuple(t),
    do: 1 + (t |> Tuple.to_list() |> Enum.reduce(0, &max(inner(&1), &2)))

  defp height(_), do: 0

  defp inner(t) when is_tuple(t), do: height(t)
  defp inner(l) when is_list(l), do: Enum.reduce(l, 0, &max(inner(&1), &2))
  defp inner(m) when is_map(m), do: m |> Map.values() |> inner()
  defp inner(_), do: 0

  defp parse_or(ts) do
    {a, rest} = parse_and(ts)
    more_or(a, rest)
  end

  defp more_or(a, ts) do
    case accept(ts, "OR") do
      {true, rest} ->
        {b, rest} = parse_and(rest)
        more_or({:or, a, b}, rest)

      _ ->
        {a, ts}
    end
  end

  defp parse_and(ts) do
    {a, rest} = parse_not(ts)
    more_and(a, rest)
  end

  defp more_and(a, ts) do
    case accept(ts, "AND") do
      {true, rest} ->
        {b, rest} = parse_not(rest)
        more_and({:and, a, b}, rest)

      _ ->
        {a, ts}
    end
  end

  defp parse_not(ts) do
    case accept(ts, "NOT") do
      {true, rest} ->
        {e, rest} = parse_not(rest)
        {{:not, e}, rest}

      _ ->
        parse_eq(ts)
    end
  end

  defp parse_eq(ts) do
    {a, rest} = parse_cmp(ts)
    more_eq(a, rest)
  end

  defp more_eq(a, ts) do
    {neg, after_not} = accept(ts, "NOT")

    cond do
      op?(ts, "=") or op?(ts, "!=") ->
        [{:op, o, _, _} | rest] = ts
        {b, rest} = parse_cmp(rest)
        more_eq({:bin, o, a, b}, rest)

      word?(ts, "IS") ->
        {is_not, rest} = accept(tl(ts), "NOT")
        {distinct, rest} = accept_all(rest, ["DISTINCT", "FROM"])
        {b, rest} = parse_cmp(rest)
        more_eq({:is, a, b, is_not != distinct}, rest)

      word?(ts, "ISNULL") ->
        more_eq({:is, a, {:lit, nil}, false}, tl(ts))

      word?(ts, "NOTNULL") ->
        more_eq({:is, a, {:lit, nil}, true}, tl(ts))

      neg and word?(after_not, "NULL") ->
        more_eq({:is, a, {:lit, nil}, true}, tl(after_not))

      word?(after_not, "IN") ->
        {set, rest} = in_set(tl(after_not))
        more_eq({:in, a, set, neg}, rest)

      word?(after_not, "LIKE") or word?(after_not, "GLOB") ->
        [{:word, {kind, _}, _, _} | rest] = after_not
        {p, rest} = parse_cmp(rest)

        {esc, rest} =
          case accept(rest, "ESCAPE") do
            {true, rest} -> parse_cmp(rest)
            _ -> {nil, rest}
          end

        more_eq({:like, String.downcase(kind), a, p, esc, neg}, rest)

      word?(after_not, "BETWEEN") ->
        {lo, rest} = parse_cmp(tl(after_not))
        rest = expect(rest, "AND")
        {hi, rest} = parse_cmp(rest)
        more_eq({:between, a, lo, hi, neg}, rest)

      word?(after_not, "MATCH") or word?(after_not, "REGEXP") ->
        unsupported(text(hd(after_not)))

      true ->
        {a, ts}
    end
  end

  defp in_set(ts) do
    ts = expect_op(ts, "(")

    cond do
      op?(ts, ")") ->
        {{:list, []}, tl(ts)}

      word?(ts, "SELECT") or word?(ts, "WITH") or word?(ts, "VALUES") ->
        {s, rest} = Select.parse(ts)
        {{:select, s}, expect_op(rest, ")")}

      true ->
        {es, rest} = list(ts, &parse/1)
        {{:list, es}, expect_op(rest, ")")}
    end
  end

  defp parse_cmp(ts) do
    {a, rest} = parse_bit(ts)
    more_binary(a, rest, ["<", "<=", ">", ">="], &parse_bit/1)
  end

  defp parse_bit(ts) do
    {a, rest} = parse_add(ts)
    more_binary(a, rest, ["&", "|", "<<", ">>"], &parse_add/1)
  end

  defp parse_add(ts) do
    {a, rest} = parse_mul(ts)
    more_binary(a, rest, ["+", "-"], &parse_mul/1)
  end

  defp parse_mul(ts) do
    {a, rest} = parse_concat(ts)
    more_binary(a, rest, ["*", "/", "%"], &parse_concat/1)
  end

  defp parse_concat(ts) do
    {a, rest} = parse_unary(ts)
    more_binary(a, rest, ["||"], &parse_unary/1)
  end

  defp more_binary(a, [{:op, o, _, _} | rest] = ts, ops, next) do
    if o in ops do
      {b, rest} = next.(rest)
      more_binary({:bin, o, a, b}, rest, ops, next)
    else
      if o in ["->"], do: unsupported("JSON's ->"), else: {a, ts}
    end
  end

  defp more_binary(a, ts, _ops, _next), do: {a, ts}

  defp parse_unary([{:op, "-", _, _} | rest]) do
    {e, rest} = parse_unary(rest)

    case e do
      {:lit, n} when is_integer(n) -> {{:lit, -n}, rest}
      {:lit, n} when is_float(n) -> {{:lit, 0.0 - n}, rest}
      _ -> {{:neg, e}, rest}
    end
  end

  defp parse_unary([{:op, "+", _, _} | rest]), do: parse_unary(rest)

  defp parse_unary([{:op, "~", _, _} | rest]) do
    {e, rest} = parse_unary(rest)
    {{:bitnot, e}, rest}
  end

  defp parse_unary(ts) do
    {e, rest} = primary(ts)
    collates(e, rest)
  end

  defp collates(e, ts) do
    case accept(ts, "COLLATE") do
      {true, rest} ->
        {name, rest} = name(rest)
        if Moss.Sql.Value.collation(name) == nil, do: fail("no such collation sequence: #{name}")
        collates({:collate, e, name}, rest)

      _ ->
        {e, ts}
    end
  end

  # -- primaries ---------------------------------------------------------------------------------

  defp primary([{:num, n, _, _} | rest]), do: {{:lit, n}, rest}
  defp primary([{:str, s, _, _} | rest]), do: {{:lit, s}, rest}
  defp primary([{:blob, b, _, _} | rest]), do: {{:lit, b}, rest}
  defp primary([{:param, p, _, _} | rest]), do: {{:param, param(p)}, rest}

  defp primary([{:op, "(", _, _} | rest]) do
    if word?(rest, "SELECT") or word?(rest, "WITH") or word?(rest, "VALUES") do
      {s, rest} = Select.parse(rest)
      {{:subquery, s}, expect_op(rest, ")")}
    else
      {e, rest} = parse(rest)
      if op?(rest, ","), do: unsupported("a row value")
      {e, expect_op(rest, ")")}
    end
  end

  # like(), glob() and the rest whose names the grammar reserves, called as functions
  defp primary([{:word, {w, orig}, _, _}, {:op, "(", _, _} | args]) when w in ["LIKE", "GLOB"],
    do: call(orig, args)

  defp primary([{:word, {w, _}, _, _} | rest] = ts) do
    case w do
      "NULL" -> {{:lit, nil}, rest}
      "CURRENT_TIMESTAMP" -> {{:now, :datetime}, rest}
      "CURRENT_DATE" -> {{:now, :date}, rest}
      "CURRENT_TIME" -> {{:now, :time}, rest}
      "CASE" -> case_expr(rest)
      "CAST" -> cast(rest)
      "EXISTS" -> exists(rest)
      "RAISE" -> unsupported("RAISE")
      _ -> name_expr(ts)
    end
  end

  defp primary([{:id, _, _, _} | _] = ts), do: name_expr(ts)
  defp primary(ts), do: syntax(ts)

  defp exists(ts) do
    ts = expect_op(ts, "(")
    {s, rest} = Select.parse(ts)
    {{:exists, s}, expect_op(rest, ")")}
  end

  defp cast(ts) do
    ts = expect_op(ts, "(")
    {e, rest} = parse(ts)
    rest = expect(rest, "AS")
    {type, rest} = type_name(rest)
    {{:cast, e, type}, expect_op(rest, ")")}
  end

  @doc "A type name: words, and an optional (n) or (n, m), as text."
  def type_name(ts) do
    {words, rest} = Enum.split_while(ts, &type_word?/1)
    if words == [], do: syntax(ts)
    name = Enum.map_join(words, " ", &text/1)

    case rest do
      [{:op, "(", _, _} | more] ->
        {_, more} = signed(more)
        {_, more} = if op?(more, ","), do: signed(tl(more)), else: {nil, more}
        {name, expect_op(more, ")")}

      _ ->
        {name, rest}
    end
  end

  defp type_word?({:word, {w, _}, _, _}), do: not reserved?(w) and w not in ~w(AUTOINCREMENT)
  defp type_word?({:id, _, _, _}), do: true
  defp type_word?(_), do: false

  defp signed([{:op, s, _, _}, {:num, n, _, _} | rest]) when s in ["+", "-"], do: {n, rest}
  defp signed([{:num, n, _, _} | rest]), do: {n, rest}
  defp signed(ts), do: syntax(ts)

  defp case_expr(ts) do
    {base, ts} = if word?(ts, "WHEN"), do: {nil, ts}, else: parse(ts)
    {whens, ts} = whens(ts, [])
    if whens == [], do: syntax(ts)

    {else_, ts} =
      case accept(ts, "ELSE") do
        {true, rest} -> parse(rest)
        _ -> {nil, ts}
      end

    {{:case, base, whens, else_}, expect(ts, "END")}
  end

  defp whens(ts, acc) do
    case accept(ts, "WHEN") do
      {true, rest} ->
        {w, rest} = parse(rest)
        rest = expect(rest, "THEN")
        {t, rest} = parse(rest)
        whens(rest, [{w, t} | acc])

      _ ->
        {Enum.reverse(acc), ts}
    end
  end

  # a column, table.column, or a function's call
  defp name_expr(ts) do
    {name, rest} = ident(ts)

    case rest do
      [{:op, "(", _, _} | args] ->
        call(name, args)

      [{:op, ".", _, _}, {:op, "*", _, _} | _] ->
        syntax(tl(tl(rest)))

      [{:op, ".", _, _} | more] ->
        {col, more} = ident(more)
        if op?(more, "."), do: unsupported("a schema-qualified name")
        {{:col, name, col}, more}

      _ ->
        {{:col, nil, name}, rest}
    end
  end

  defp call(name, ts) do
    lname = String.downcase(name)

    {args, rest} =
      cond do
        op?(ts, "*") -> {:star, expect_op(tl(ts), ")")}
        op?(ts, ")") -> {{false, []}, tl(ts)}
        true -> call_args(ts)
      end

    if word?(rest, "FILTER"), do: unsupported("FILTER")
    if word?(rest, "OVER"), do: unsupported("a window function (OVER)")

    case args do
      :star -> {{:fn, lname, :star, false}, rest}
      {distinct, list} -> {{:fn, lname, list, distinct}, rest}
    end
  end

  defp call_args(ts) do
    {distinct, ts} = accept(ts, "DISTINCT")
    {_, ts} = if distinct, do: {false, ts}, else: accept(ts, "ALL")
    {es, rest} = list(ts, &parse/1)
    if word?(rest, "ORDER"), do: unsupported("ORDER BY inside a function's arguments")
    {{distinct, es}, expect_op(rest, ")")}
  end
end

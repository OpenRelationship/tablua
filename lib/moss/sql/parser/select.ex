defmodule Moss.Sql.Parser.Select do
  @moduledoc """
  SELECT: `SELECT [DISTINCT|ALL] cols [FROM ...] [WHERE] [GROUP BY [HAVING]]`,
  joined by UNION [ALL], INTERSECT or EXCEPT, then ORDER BY and LIMIT.

  A select is `%{cores: [{op, core}], order: [...], limit: e, offset: e}`
  (the first core's op is nil); a core is `%{distinct, cols, from, where,
  group, having}`. A column is `:star`, `{:tstar, table}` or
  `{:expr, e, alias, text}`. FROM is a list of sources, each
  `%{source: {:table, name} | {:select, s}, as, join: :first | :inner |
  :left | :cross, on, using}`. An ORDER BY term is `{e, :asc | :desc,
  nulls :first | :last | nil}`.
  """
  import Moss.Sql.Parser.Tokens
  alias Moss.Sql.Parser.Expr

  def parse(ts) do
    if word?(ts, "WITH"), do: unsupported("WITH (a common table expression)")
    if word?(ts, "VALUES"), do: unsupported("VALUES as a query")
    {cores, rest} = cores(ts, nil, [])
    {order, rest} = order_by(rest)
    {limit, offset, rest} = limit(rest)
    {%{cores: cores, order: order, limit: limit, offset: offset}, rest}
  end

  defp cores(ts, op, acc) do
    {core, rest} = core(ts)
    acc = [{op, core} | acc]

    cond do
      word?(rest, "UNION") ->
        {all, rest} = accept(tl(rest), "ALL")
        cores(rest, if(all, do: :union_all, else: :union), acc)

      word?(rest, "INTERSECT") ->
        cores(tl(rest), :intersect, acc)

      word?(rest, "EXCEPT") ->
        cores(tl(rest), :except, acc)

      true ->
        {Enum.reverse(acc), rest}
    end
  end

  defp core(ts) do
    ts = expect(ts, "SELECT")
    {distinct, ts} = accept(ts, "DISTINCT")
    {_, ts} = if distinct, do: {false, ts}, else: accept(ts, "ALL")
    {cols, ts} = list(ts, &column/1)
    {from, ts} = if word?(ts, "FROM"), do: from(tl(ts)), else: {[], ts}
    {where, ts} = clause(ts, "WHERE")

    {group, ts} =
      case accept_all(ts, ["GROUP", "BY"]) do
        {true, rest} -> list(rest, &Expr.parse/1)
        _ -> {[], ts}
      end

    {having, ts} = clause(ts, "HAVING")
    if word?(ts, "WINDOW"), do: unsupported("WINDOW")

    {%{distinct: distinct, cols: cols, from: from, where: where, group: group, having: having},
     ts}
  end

  def clause(ts, w) do
    case accept(ts, w) do
      {true, rest} -> Expr.parse(rest)
      _ -> {nil, ts}
    end
  end

  defp column([{:op, "*", _, _} | rest]), do: {:star, rest}

  defp column([t, {:op, ".", _, _}, {:op, "*", _, _} | rest] = ts) do
    {name, _} = ident(ts)
    _ = t
    {{:tstar, name}, rest}
  end

  defp column(ts) do
    {e, rest} = Expr.parse(ts)
    text = span(ts, rest)
    {as, rest} = alias_(rest)
    {{:expr, e, as, text}, rest}
  end

  # [AS] alias
  def alias_(ts) do
    case accept(ts, "AS") do
      {true, rest} ->
        name(rest)

      _ ->
        case ts do
          [{:str, s, _, _} | rest] -> {s, rest}
          _ -> if ident?(ts), do: ident(ts), else: {nil, ts}
        end
    end
  end

  # -- FROM --------------------------------------------------------------------------------------

  def from(ts) do
    {first, rest} = source(ts, :first)
    joins(rest, [first])
  end

  defp joins(ts, acc) do
    case join_op(ts) do
      {nil, _} ->
        {Enum.reverse(acc), ts}

      {kind, rest} ->
        {src, rest} = source(rest, kind)
        {src, rest} = constraint(src, rest)
        joins(rest, [src | acc])
    end
  end

  defp join_op([{:op, ",", _, _} | rest]), do: {:cross, rest}

  defp join_op(ts) do
    cond do
      word?(ts, "NATURAL") ->
        unsupported("NATURAL JOIN")

      word?(ts, "RIGHT") or word?(ts, "FULL") ->
        unsupported("#{String.upcase(text(hd(ts)))} JOIN")

      word?(ts, "JOIN") ->
        {:inner, tl(ts)}

      word?(ts, "INNER") ->
        {:inner, expect(tl(ts), "JOIN")}

      word?(ts, "CROSS") ->
        {:cross, expect(tl(ts), "JOIN")}

      word?(ts, "LEFT") ->
        {:left, ts |> tl() |> accept("OUTER") |> elem(1) |> expect("JOIN")}

      true ->
        {nil, ts}
    end
  end

  defp source([{:op, "(", _, _} | rest], kind) do
    if not (word?(rest, "SELECT") or word?(rest, "WITH") or word?(rest, "VALUES")),
      do: unsupported("a parenthesized join")

    {s, rest} = parse(rest)
    rest = expect_op(rest, ")")
    {as, rest} = alias_(rest)
    {%{source: {:select, s}, as: as, join: kind, on: nil, using: nil}, rest}
  end

  defp source(ts, kind) do
    {name, rest} = ident(ts)

    {name, rest} =
      if op?(rest, "."),
        do:
          (fn ->
             if String.downcase(name) == "main",
               do: ident(tl(rest)),
               else: unsupported("another database's table")
           end).(),
        else: {name, rest}

    if op?(rest, "("), do: unsupported("a table-valued function")

    indexed? = fn ts ->
      (word?(ts, "INDEXED") and word?(tl(ts), "BY")) or
        (word?(ts, "NOT") and word?(tl(ts), "INDEXED"))
    end

    if indexed?.(rest), do: unsupported("INDEXED BY")
    {as, rest} = alias_(rest)
    if indexed?.(rest), do: unsupported("INDEXED BY")
    {%{source: {:table, name}, as: as, join: kind, on: nil, using: nil}, rest}
  end

  defp constraint(src, ts) do
    cond do
      word?(ts, "ON") ->
        {e, rest} = Expr.parse(tl(ts))
        {%{src | on: e}, rest}

      word?(ts, "USING") ->
        rest = expect_op(tl(ts), "(")
        {cols, rest} = list(rest, &ident/1)
        {%{src | using: cols}, expect_op(rest, ")")}

      true ->
        {src, ts}
    end
  end

  # -- ORDER BY, LIMIT ---------------------------------------------------------------------------

  def order_by(ts) do
    case accept_all(ts, ["ORDER", "BY"]) do
      {true, rest} -> list(rest, &term/1)
      _ -> {[], ts}
    end
  end

  defp term(ts) do
    {e, rest} = Expr.parse(ts)

    {dir, rest} =
      cond do
        word?(rest, "ASC") -> {:asc, tl(rest)}
        word?(rest, "DESC") -> {:desc, tl(rest)}
        true -> {:asc, rest}
      end

    {nulls, rest} =
      cond do
        match?({true, _}, accept_all(rest, ["NULLS", "FIRST"])) -> {:first, Enum.drop(rest, 2)}
        match?({true, _}, accept_all(rest, ["NULLS", "LAST"])) -> {:last, Enum.drop(rest, 2)}
        true -> {nil, rest}
      end

    {{e, dir, nulls}, rest}
  end

  def limit(ts) do
    case accept(ts, "LIMIT") do
      {true, rest} ->
        {l, rest} = Expr.parse(rest)

        cond do
          word?(rest, "OFFSET") ->
            {o, rest} = Expr.parse(tl(rest))
            {l, o, rest}

          op?(rest, ",") ->
            # LIMIT offset, count
            {c, rest} = Expr.parse(tl(rest))
            {c, l, rest}

          true ->
            {l, nil, rest}
        end

      _ ->
        {nil, nil, ts}
    end
  end
end

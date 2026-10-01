defmodule Moss.Sql.Parser.Tokens do
  @moduledoc """
  The parser's reading of a token list: peeking at words and operators,
  taking identifiers, and SQLite's own errors (`near "x": syntax error`,
  `incomplete input`). Errors are thrown as `{:sql_error, message}` and
  caught at the statement's edge (`Moss.Sql.Parser.parse/1`).
  """

  # words a bare identifier cannot be, because the grammar reads them as its own
  @reserved MapSet.new(~w(
    ADD ALL ALTER AND AS BETWEEN BY CASE CAST CHECK COLLATE CONSTRAINT CREATE CROSS DEFAULT DELETE DISTINCT
    DROP ELSE END ESCAPE EXCEPT EXISTS FOREIGN FROM FULL GLOB GROUP HAVING IN INDEX INNER INSERT INTERSECT
    INTO IS ISNULL JOIN LEFT LIKE LIMIT MATCH NATURAL NOT NOTNULL NULL ON OR ORDER OUTER PRIMARY REFERENCES
    REGEXP RETURNING RIGHT SELECT SET TABLE THEN UNION UNIQUE UPDATE USING VALUES WHEN WHERE WINDOW WITH
  ))

  def reserved?(upper), do: MapSet.member?(@reserved, upper)

  def fail(msg), do: throw({:sql_error, msg})

  @doc "A syntax error at the first token of `ts`."
  def syntax([]), do: fail("incomplete input")
  def syntax([{:semi, _, _, _} | _]), do: fail("incomplete input")
  def syntax([tok | _]), do: fail(~s(near "#{text(tok)}": syntax error))

  @doc "A token as the agent wrote it."
  def text({:word, {_, orig}, _, _}), do: orig
  def text({_, _, from, to}), do: binary_part(Process.get(:sql_src, ""), from, to - from)

  def word?([{:word, {w, _}, _, _} | _], w), do: true
  def word?(_, _), do: false

  def op?([{:op, o, _, _} | _], o), do: true
  def op?(_, _), do: false

  def accept(ts, w) do
    if word?(ts, w), do: {true, tl(ts)}, else: {false, ts}
  end

  def accept_op(ts, o) do
    if op?(ts, o), do: {true, tl(ts)}, else: {false, ts}
  end

  def expect(ts, w), do: if(word?(ts, w), do: tl(ts), else: syntax(ts))
  def expect_op(ts, o), do: if(op?(ts, o), do: tl(ts), else: syntax(ts))

  @doc "Several words in a row, all or none."
  def accept_all(ts, [w | more]) do
    case accept(ts, w) do
      {true, rest} ->
        case accept_all(rest, more) do
          {true, rest} -> {true, rest}
          _ -> {false, ts}
        end

      _ ->
        {false, ts}
    end
  end

  def accept_all(ts, []), do: {true, ts}

  @doc "An identifier: a quoted one, or a word the grammar does not reserve."
  def ident([{:id, name, _, _} | rest]), do: {name, rest}

  def ident([{:word, {up, orig}, _, _} | rest] = ts) do
    if reserved?(up), do: syntax(ts), else: {orig, rest}
  end

  def ident(ts), do: syntax(ts)

  @doc "An identifier, or a string where SQLite takes one as a name (an alias, a column)."
  def name([{:str, s, _, _} | rest]), do: {s, rest}
  def name(ts), do: ident(ts)

  def ident?([{:id, _, _, _} | _]), do: true
  def ident?([{:word, {up, _}, _, _} | _]), do: not reserved?(up)
  def ident?(_), do: false

  @doc "The source text from the first token of `ts` up to (not including) the first of `rest`."
  def span(ts, rest) do
    taken = Enum.take(ts, length(ts) - length(rest))

    case taken do
      [] ->
        ""

      [{_, _, from, _} | _] ->
        {_, _, _, to} = List.last(taken)
        binary_part(Process.get(:sql_src, ""), from, to - from)
    end
  end

  @doc "A comma-separated list of what `f` reads."
  def list(ts, f) do
    {x, rest} = f.(ts)

    case rest do
      [{:op, ",", _, _} | more] ->
        {xs, rest} = list(more, f)
        {[x | xs], rest}

      _ ->
        {[x], rest}
    end
  end

  @doc "A parameter's index: `?` the next, `?N` N, a name the index it first had."
  def param({:n, n}) do
    if n < 1 or n > 32_766, do: fail("variable number must be between ?1 and ?32766")
    Process.put(:sql_nparams, max(Process.get(:sql_nparams, 0), n))
    n
  end

  def param(:next) do
    n = Process.get(:sql_nparams, 0) + 1
    Process.put(:sql_nparams, n)
    n
  end

  def param({:name, name}) do
    names = Process.get(:sql_pnames, %{})

    case names do
      %{^name => n} ->
        n

      _ ->
        n = param(:next)
        Process.put(:sql_pnames, Map.put(names, name, n))
        n
    end
  end

  def unsupported(what),
    do: fail("#{what} is not supported (the database speaks a subset of SQLite: help lua)")
end

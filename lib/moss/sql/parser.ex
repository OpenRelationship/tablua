defmodule Moss.Sql.Parser do
  @moduledoc """
  The agent's SQL as statements, parsed in Elixir (Arock PROJECT.md §14.7
  item 9: no SQL an agent writes reaches SQLite's C). `parse/1` gives a list
  of `{statement, parameter_count}`, or `{:error, message}` worded as
  SQLite words it.

  Statements: SELECT (`Parser.Select`); INSERT [OR IGNORE|REPLACE|ABORT]
  (and REPLACE INTO) with VALUES, SELECT or DEFAULT VALUES, ON CONFLICT ...
  DO UPDATE/NOTHING and RETURNING; UPDATE and DELETE with WHERE and
  RETURNING; CREATE TABLE and CREATE [UNIQUE] INDEX (IF NOT EXISTS), DROP
  TABLE/INDEX (IF EXISTS), ALTER TABLE ADD COLUMN; BEGIN, COMMIT/END and
  ROLLBACK. Anything else is refused by name. A statement is at most
  #{div(1_048_576, 1024)} KB.
  """
  import Moss.Sql.Parser.Tokens
  alias Moss.Sql.Lexer
  alias Moss.Sql.Parser.{Ddl, Expr, Select}

  @max_bytes 1_048_576

  def parse(sql) when byte_size(sql) > @max_bytes,
    do: {:error, "string or blob too big: a statement is at most #{div(@max_bytes, 1024)} KB"}

  def parse(sql) do
    Process.put(:sql_src, sql)

    with {:ok, ts} <- Lexer.tokens(sql) do
      {:ok, statements(ts, [])}
    end
  catch
    {:sql_error, msg} -> {:error, msg}
  after
    Process.delete(:sql_src)
    Process.delete(:sql_depth)
  end

  defp statements([], acc), do: Enum.reverse(acc)
  defp statements([{:semi, _, _, _} | rest], acc), do: statements(rest, acc)

  defp statements(ts, acc) do
    Process.put(:sql_nparams, 0)
    Process.put(:sql_pnames, %{})
    Process.put(:sql_depth, 0)
    {st, rest} = statement(ts)

    case rest do
      [] -> :ok
      [{:semi, _, _, _} | _] -> :ok
      _ -> syntax(rest)
    end

    statements(rest, [{st, Process.get(:sql_nparams)} | acc])
  end

  defp statement([{:word, {w, _}, _, _} | rest] = ts) do
    case w do
      "SELECT" ->
        select(ts)

      "WITH" ->
        select(ts)

      "VALUES" ->
        select(ts)

      "INSERT" ->
        insert(rest, :abort)

      "REPLACE" ->
        insert(rest, :replace)

      "UPDATE" ->
        update(rest)

      "DELETE" ->
        delete(rest)

      "CREATE" ->
        Ddl.create(ts)

      "DROP" ->
        Ddl.drop(rest)

      "ALTER" ->
        Ddl.alter(ts)

      "BEGIN" ->
        begin(rest)

      "COMMIT" ->
        {{:commit}, transaction_word(rest)}

      "END" ->
        {{:commit}, transaction_word(rest)}

      "ROLLBACK" ->
        rollback(rest)

      other
      when other in ~w(PRAGMA ATTACH DETACH VACUUM ANALYZE REINDEX SAVEPOINT RELEASE EXPLAIN) ->
        unsupported(other)

      _ ->
        syntax(ts)
    end
  end

  defp statement(ts), do: syntax(ts)

  defp select(ts) do
    {s, rest} = Select.parse(ts)
    {{:select, s}, rest}
  end

  defp begin(ts) do
    ts =
      if word?(ts, "DEFERRED") or word?(ts, "IMMEDIATE") or word?(ts, "EXCLUSIVE"),
        do: tl(ts),
        else: ts

    {{:begin}, transaction_word(ts)}
  end

  defp rollback(ts) do
    ts = transaction_word(ts)
    if word?(ts, "TO"), do: unsupported("ROLLBACK TO (savepoints)")
    {{:rollback}, ts}
  end

  defp transaction_word(ts), do: ts |> accept("TRANSACTION") |> elem(1)

  # -- INSERT ------------------------------------------------------------------------------------

  defp insert(ts, conflict) do
    {conflict, ts} =
      case accept(ts, "OR") do
        {true, [{:word, {w, _}, _, _} | rest]} when w in ~w(IGNORE REPLACE ABORT FAIL ROLLBACK) ->
          {conflict_kind(w), rest}

        {true, rest} ->
          syntax(rest)

        _ ->
          {conflict, ts}
      end

    ts = expect(ts, "INTO")
    {table, ts} = table_name(ts)
    {_, ts} = if word?(ts, "AS"), do: Select.alias_(ts), else: {nil, ts}

    {cols, ts} =
      if op?(ts, "(") do
        {cols, rest} = list(tl(ts), &ident/1)
        {cols, expect_op(rest, ")")}
      else
        {nil, ts}
      end

    {source, ts} =
      cond do
        word?(ts, "VALUES") ->
          {rows, rest} = list(tl(ts), &values_row/1)
          {{:values, rows}, rest}

        word?(ts, "DEFAULT") ->
          {:default, ts |> tl() |> expect("VALUES")}

        word?(ts, "SELECT") or word?(ts, "WITH") ->
          {s, rest} = Select.parse(ts)
          {{:select, s}, rest}

        true ->
          syntax(ts)
      end

    {upsert, ts} = upserts(ts, [])
    {returning, ts} = returning(ts)

    {{:insert,
      %{
        conflict: conflict,
        table: table,
        cols: cols,
        source: source,
        upsert: upsert,
        returning: returning
      }}, ts}
  end

  defp conflict_kind("IGNORE"), do: :ignore
  defp conflict_kind("REPLACE"), do: :replace
  defp conflict_kind(w) when w in ["ABORT", "FAIL", "ROLLBACK"], do: :abort

  defp values_row(ts) do
    ts = expect_op(ts, "(")
    {es, rest} = list(ts, &Expr.parse/1)
    {es, expect_op(rest, ")")}
  end

  defp upserts(ts, acc) do
    case accept_all(ts, ["ON", "CONFLICT"]) do
      {true, rest} ->
        {target, rest} =
          if op?(rest, "(") do
            {cols, more} = list(tl(rest), &conflict_col/1)
            more = expect_op(more, ")")
            if word?(more, "WHERE"), do: unsupported("a partial-index conflict target")
            {cols, more}
          else
            {nil, rest}
          end

        rest = expect(rest, "DO")

        {action, rest} =
          cond do
            word?(rest, "NOTHING") ->
              {:nothing, tl(rest)}

            word?(rest, "UPDATE") ->
              rest = expect(tl(rest), "SET")
              {sets, rest} = list(rest, &set/1)
              {where, rest} = Select.clause(rest, "WHERE")
              {{:update, sets, where}, rest}

            true ->
              syntax(rest)
          end

        upserts(rest, [%{target: target, action: action} | acc])

      _ ->
        {Enum.reverse(acc), ts}
    end
  end

  defp conflict_col(ts) do
    {name, rest} = ident(ts)
    rest = if word?(rest, "COLLATE"), do: Enum.drop(rest, 2), else: rest
    rest = if word?(rest, "ASC") or word?(rest, "DESC"), do: tl(rest), else: rest
    {name, rest}
  end

  defp returning(ts) do
    case accept(ts, "RETURNING") do
      {true, rest} ->
        {cols, rest} = list(rest, &returning_col/1)
        {cols, rest}

      _ ->
        {nil, ts}
    end
  end

  defp returning_col([{:op, "*", _, _} | rest]), do: {:star, rest}

  defp returning_col(ts) do
    {e, rest} = Expr.parse(ts)
    text = span(ts, rest)
    {as, rest} = Select.alias_(rest)
    {{:expr, e, as, text}, rest}
  end

  # -- UPDATE, DELETE ----------------------------------------------------------------------------

  defp update(ts) do
    {conflict, ts} =
      case accept(ts, "OR") do
        {true, [{:word, {w, _}, _, _} | rest]} when w in ~w(IGNORE REPLACE ABORT FAIL ROLLBACK) ->
          {conflict_kind(w), rest}

        {true, rest} ->
          syntax(rest)

        _ ->
          {:abort, ts}
      end

    {table, ts} = table_name(ts)
    {as, ts} = if word?(ts, "SET"), do: {nil, ts}, else: Select.alias_(ts)
    ts = expect(ts, "SET")
    {sets, ts} = list(ts, &set/1)
    if word?(ts, "FROM"), do: unsupported("UPDATE ... FROM")
    {where, ts} = Select.clause(ts, "WHERE")
    no_order_limit(ts)
    {returning, ts} = returning(ts)

    {{:update,
      %{conflict: conflict, table: table, as: as, sets: sets, where: where, returning: returning}},
     ts}
  end

  defp set(ts) do
    if op?(ts, "("), do: unsupported("a column list in SET")
    {col, rest} = ident(ts)
    rest = expect_op(rest, "=")
    {e, rest} = Expr.parse(rest)
    {{col, e}, rest}
  end

  defp delete(ts) do
    ts = expect(ts, "FROM")
    {table, ts} = table_name(ts)

    {as, ts} =
      if word?(ts, "WHERE") or word?(ts, "RETURNING"), do: {nil, ts}, else: Select.alias_(ts)

    {where, ts} = Select.clause(ts, "WHERE")
    no_order_limit(ts)
    {returning, ts} = returning(ts)
    {{:delete, %{table: table, as: as, where: where, returning: returning}}, ts}
  end

  defp no_order_limit(ts) do
    if word?(ts, "ORDER") or word?(ts, "LIMIT"),
      do: unsupported("ORDER BY or LIMIT on UPDATE and DELETE")
  end

  @doc "A table's name, `main.` allowed before it."
  def table_name(ts) do
    {name, rest} = ident(ts)

    case rest do
      [{:op, ".", _, _} | more] ->
        if String.downcase(name) in ["main"],
          do: ident(more),
          else: unsupported("another database (#{name}.)")

      _ ->
        {name, rest}
    end
  end
end

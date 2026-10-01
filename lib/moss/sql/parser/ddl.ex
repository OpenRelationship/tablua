defmodule Moss.Sql.Parser.Ddl do
  @moduledoc """
  The schema's statements: CREATE TABLE (columns with PRIMARY KEY,
  AUTOINCREMENT, NOT NULL, UNIQUE, CHECK, DEFAULT, COLLATE and REFERENCES,
  which SQLite keeps but does not enforce by default; table constraints
  PRIMARY KEY, UNIQUE, CHECK, FOREIGN KEY), CREATE TABLE ... AS SELECT,
  CREATE [UNIQUE] INDEX, DROP TABLE/INDEX and ALTER TABLE ADD COLUMN.

  A column is `%{name, type, pk, notnull, unique, checks, default, collate}`;
  a constraint's conflict clause (`ON CONFLICT REPLACE`...) is kept as
  `:abort`, `:ignore` or `:replace`.
  """
  import Moss.Sql.Parser.Tokens
  alias Moss.Sql.Parser
  alias Moss.Sql.Parser.{Expr, Select}

  # SQLite keeps `CREATE TABLE ` (or INDEX) and the text from the name on, whatever came before the name
  def create(ts) do
    {{kind, m}, rest} = create_(tl(ts))
    {head, from} = m.text_from
    sql = if kind == :create_table_as, do: nil, else: head <> span(from, rest)
    {{kind, m |> Map.delete(:text_from) |> Map.put(:sql, sql)}, rest}
  end

  defp create_(ts) do
    ts = if word?(ts, "TEMP") or word?(ts, "TEMPORARY"), do: tl(ts), else: ts

    cond do
      word?(ts, "TABLE") -> table(tl(ts))
      word?(ts, "UNIQUE") -> index(expect(tl(ts), "INDEX"), true)
      word?(ts, "INDEX") -> index(tl(ts), false)
      word?(ts, "VIEW") -> unsupported("CREATE VIEW")
      word?(ts, "TRIGGER") -> unsupported("CREATE TRIGGER")
      word?(ts, "VIRTUAL") -> unsupported("CREATE VIRTUAL TABLE")
      true -> syntax(ts)
    end
  end

  defp if_not_exists(ts) do
    case accept_all(ts, ["IF", "NOT", "EXISTS"]) do
      {true, rest} -> {true, rest}
      _ -> {false, ts}
    end
  end

  defp table(ts) do
    {ine, ts} = if_not_exists(ts)
    from = name_start(ts)
    {name, ts} = Parser.table_name(ts)

    cond do
      word?(ts, "AS") ->
        {s, rest} = Select.parse(tl(ts))

        {{:create_table_as, %{name: name, if_not_exists: ine, select: s, text_from: {"", from}}},
         rest}

      true ->
        ts = expect_op(ts, "(")
        {items, ts} = list(ts, &item/1)
        ts = expect_op(ts, ")")
        if word?(ts, "WITHOUT"), do: unsupported("WITHOUT ROWID")
        if word?(ts, "STRICT"), do: unsupported("a STRICT table")
        {cols, cons} = Enum.split_with(items, &match?({:col, _}, &1))

        {{:create_table,
          %{
            name: name,
            if_not_exists: ine,
            cols: Enum.map(cols, &elem(&1, 1)),
            constraints: cons,
            text_from: {"CREATE TABLE ", from}
          }}, ts}
    end
  end

  # a column, or a table constraint
  defp item(ts) do
    {cname, ts} = constraint_name(ts)

    cond do
      word?(ts, "PRIMARY") ->
        ts = ts |> tl() |> expect("KEY")
        {cols, ts} = paren_cols(ts)
        {conflict, ts} = conflict(ts)
        {{:pk, %{cols: cols, conflict: conflict}}, ts}

      word?(ts, "UNIQUE") ->
        {cols, ts} = paren_cols(tl(ts))
        {conflict, ts} = conflict(ts)
        {{:unique, %{cols: cols, conflict: conflict}}, ts}

      word?(ts, "CHECK") ->
        {check, ts} = check(tl(ts), cname)
        {{:check, check}, ts}

      word?(ts, "FOREIGN") ->
        ts = ts |> tl() |> expect("KEY")
        {_, ts} = paren_cols(ts)
        {{:fk, nil}, references(expect(ts, "REFERENCES"))}

      cname != nil ->
        syntax(ts)

      true ->
        {col, ts} = column(ts)
        {{:col, col}, ts}
    end
  end

  defp constraint_name(ts) do
    case accept(ts, "CONSTRAINT") do
      {true, rest} -> name(rest)
      _ -> {nil, ts}
    end
  end

  defp paren_cols(ts) do
    ts = expect_op(ts, "(")

    {cols, rest} =
      list(ts, fn t ->
        {n, r} = ident(t)
        {coll, r} = if word?(r, "COLLATE"), do: name(tl(r)), else: {nil, r}
        r = if word?(r, "ASC") or word?(r, "DESC"), do: tl(r), else: r
        {{n, coll}, r}
      end)

    {cols, expect_op(rest, ")")}
  end

  defp conflict(ts) do
    case accept_all(ts, ["ON", "CONFLICT"]) do
      {true, [{:word, {w, _}, _, _} | rest]} when w in ~w(ROLLBACK ABORT FAIL IGNORE REPLACE) ->
        kind =
          case w do
            "IGNORE" -> :ignore
            "REPLACE" -> :replace
            _ -> :abort
          end

        {kind, rest}

      {true, rest} ->
        syntax(rest)

      _ ->
        {nil, ts}
    end
  end

  defp check(ts, cname) do
    ts = expect_op(ts, "(")
    {e, rest} = Expr.parse(ts)
    text = span(ts, rest)
    {%{expr: e, text: cname || text}, expect_op(rest, ")")}
  end

  # REFERENCES t [(cols)] and its ON DELETE/UPDATE, MATCH and DEFERRABLE clauses, kept unenforced as SQLite does
  defp references(ts) do
    {_, ts} = ident(ts)
    ts = if op?(ts, "("), do: elem(paren_cols(ts), 1), else: ts
    fk_clauses(ts)
  end

  defp fk_clauses(ts) do
    cond do
      word?(ts, "ON") and (word?(tl(ts), "DELETE") or word?(tl(ts), "UPDATE")) ->
        rest = Enum.drop(ts, 2)

        rest =
          cond do
            word?(rest, "SET") -> Enum.drop(rest, 2)
            word?(rest, "NO") -> Enum.drop(rest, 2)
            word?(rest, "CASCADE") or word?(rest, "RESTRICT") -> tl(rest)
            true -> syntax(rest)
          end

        fk_clauses(rest)

      word?(ts, "MATCH") ->
        fk_clauses(Enum.drop(ts, 2))

      word?(ts, "NOT") and word?(tl(ts), "DEFERRABLE") ->
        fk_clauses(tl(ts))

      word?(ts, "DEFERRABLE") ->
        rest = tl(ts)
        rest = if word?(rest, "INITIALLY"), do: Enum.drop(rest, 2), else: rest
        fk_clauses(rest)

      true ->
        ts
    end
  end

  @doc "A column's definition: its name, type and constraints."
  def column(ts) do
    {name, ts} = ident(ts)

    {type, ts} =
      if type_start?(ts), do: Expr.type_name(ts), else: {nil, ts}

    col = %{
      name: name,
      type: type,
      pk: nil,
      notnull: nil,
      unique: nil,
      checks: [],
      default: nil,
      collate: nil
    }

    col_constraints(col, ts)
  end

  defp type_start?([{:word, {w, _}, _, _} | _]),
    do: not reserved?(w) and w not in ~w(AUTOINCREMENT GENERATED)

  defp type_start?([{:id, _, _, _} | _]), do: true
  defp type_start?(_), do: false

  defp col_constraints(col, ts) do
    {cname, ts} = constraint_name(ts)

    cond do
      word?(ts, "PRIMARY") ->
        ts = ts |> tl() |> expect("KEY")

        {dir, ts} =
          if word?(ts, "ASC") or word?(ts, "DESC"), do: {hd(ts), tl(ts)}, else: {nil, ts}

        {conflict, ts} = conflict(ts)
        {autoinc, ts} = accept(ts, "AUTOINCREMENT")
        desc = match?({:word, {"DESC", _}, _, _}, dir)
        col_constraints(%{col | pk: %{autoinc: autoinc, conflict: conflict, desc: desc}}, ts)

      word?(ts, "NOT") ->
        ts = ts |> tl() |> expect("NULL")
        {conflict, ts} = conflict(ts)
        col_constraints(%{col | notnull: conflict || :abort}, ts)

      word?(ts, "NULL") ->
        {_, ts} = conflict(tl(ts))
        col_constraints(col, ts)

      word?(ts, "UNIQUE") ->
        {conflict, ts} = conflict(tl(ts))
        col_constraints(%{col | unique: conflict || :abort}, ts)

      word?(ts, "CHECK") ->
        {c, ts} = check(tl(ts), cname)
        col_constraints(%{col | checks: col.checks ++ [c]}, ts)

      word?(ts, "DEFAULT") ->
        {d, ts} = default(tl(ts))
        col_constraints(%{col | default: d}, ts)

      word?(ts, "COLLATE") ->
        {c, ts} = name(tl(ts))
        if Moss.Sql.Value.collation(c) == nil, do: fail("no such collation sequence: #{c}")
        col_constraints(%{col | collate: c}, ts)

      word?(ts, "REFERENCES") ->
        col_constraints(col, references(tl(ts)))

      word?(ts, "GENERATED") or word?(ts, "AS") ->
        unsupported("a generated column")

      cname != nil ->
        syntax(ts)

      true ->
        {col, ts}
    end
  end

  defp default([{:op, "(", _, _} | rest]) do
    {e, rest} = Expr.parse(rest)
    {e, expect_op(rest, ")")}
  end

  defp default([{:op, s, _, _}, {:num, n, _, _} | rest]) when s in ["+", "-"],
    do: {{:lit, if(s == "-", do: -n, else: n)}, rest}

  defp default([{k, v, _, _} | rest]) when k in [:num, :str, :blob], do: {{:lit, v}, rest}

  defp default([{:word, {w, _}, _, _} | rest])
       when w in ~w(NULL TRUE FALSE CURRENT_TIMESTAMP CURRENT_DATE CURRENT_TIME) do
    case w do
      "NULL" -> {{:lit, nil}, rest}
      "TRUE" -> {{:lit, 1}, rest}
      "FALSE" -> {{:lit, 0}, rest}
      "CURRENT_TIMESTAMP" -> {{:now, :datetime}, rest}
      "CURRENT_DATE" -> {{:now, :date}, rest}
      "CURRENT_TIME" -> {{:now, :time}, rest}
    end
  end

  defp default([{:word, {w, orig}, _, _} | rest]) do
    if reserved?(w), do: syntax([{:word, {w, orig}, 0, 0}]), else: {{:lit, orig}, rest}
  end

  defp default([{:id, s, _, _} | rest]), do: {{:lit, s}, rest}
  defp default(ts), do: syntax(ts)

  # the tokens from the object's own name (past `main.`)
  defp name_start([_, {:op, ".", _, _} | rest]), do: rest
  defp name_start(ts), do: ts

  defp index(ts, unique) do
    {ine, ts} = if_not_exists(ts)
    from = name_start(ts)
    {name, ts} = Parser.table_name(ts)
    ts = expect(ts, "ON")
    {table, ts} = ident(ts)
    ts = expect_op(ts, "(")

    {cols, ts} =
      list(ts, fn t ->
        {n, r} =
          case t do
            [{k, _, _, _}, {:op, nx, _, _} | _] when k in [:word, :id] and nx in [",", ")"] ->
              ident(t)

            [{k, _, _, _}, {:word, {nx, _}, _, _} | _]
            when k in [:word, :id] and nx in ~w(COLLATE ASC DESC) ->
              ident(t)

            _ ->
              unsupported("an index on an expression")
          end

        {coll, r} = if word?(r, "COLLATE"), do: name(tl(r)), else: {nil, r}
        r = if word?(r, "ASC") or word?(r, "DESC"), do: tl(r), else: r
        {{n, coll}, r}
      end)

    ts = expect_op(ts, ")")
    if word?(ts, "WHERE"), do: unsupported("a partial index (CREATE INDEX ... WHERE)")
    head = if unique, do: "CREATE UNIQUE INDEX ", else: "CREATE INDEX "

    {{:create_index,
      %{
        name: name,
        table: table,
        unique: unique,
        if_not_exists: ine,
        cols: cols,
        text_from: {head, from}
      }}, ts}
  end

  def drop(ts) do
    {kind, ts} =
      cond do
        word?(ts, "TABLE") -> {:drop_table, tl(ts)}
        word?(ts, "INDEX") -> {:drop_index, tl(ts)}
        word?(ts, "VIEW") -> unsupported("DROP VIEW")
        word?(ts, "TRIGGER") -> unsupported("DROP TRIGGER")
        true -> syntax(ts)
      end

    {ie, ts} =
      case accept_all(ts, ["IF", "EXISTS"]) do
        {true, rest} -> {true, rest}
        _ -> {false, ts}
      end

    {name, ts} = Parser.table_name(ts)
    {{kind, %{name: name, if_exists: ie}}, ts}
  end

  def alter(ts) do
    ts = ts |> tl() |> expect("TABLE")
    {table, ts} = Parser.table_name(ts)

    cond do
      word?(ts, "ADD") ->
        {_, rest} = accept(tl(ts), "COLUMN")
        {col, after_col} = column(rest)
        {{:alter_add, %{table: table, col: col, text: span(rest, after_col)}}, after_col}

      word?(ts, "RENAME") ->
        unsupported("ALTER TABLE ... RENAME")

      word?(ts, "DROP") ->
        unsupported("ALTER TABLE ... DROP COLUMN")

      true ->
        syntax(ts)
    end
  end
end

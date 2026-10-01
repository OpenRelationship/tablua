defmodule Moss.Sql.Insert do
  @moduledoc """
  INSERT: VALUES (one row or many), SELECT, or DEFAULT VALUES, into all
  columns or those named; OR IGNORE, OR REPLACE (and REPLACE INTO); and
  upserts, `ON CONFLICT [(cols)] DO NOTHING` or `DO UPDATE SET ... [WHERE]`
  with `excluded.` the row that was turned away. Gives `{db, changes,
  returned rows}`.
  """
  alias Moss.Sql.{Change, Compile, Ops, Row, Schema, Select, Table}

  def run(db, st, ctx) do
    tkey = String.downcase(st.table)

    if tkey in ["sqlite_master", "sqlite_schema"],
      do: Ops.fail("table #{st.table} may not be modified")

    t = db.tables[tkey] || Ops.fail("no such table: #{st.table}")
    targets = targets(t, st.cols)
    rows = source_rows(st, t, targets, ctx)
    s = Row.scope(t, nil, ctx)
    ret = Row.returning(st.returning, t, s)
    upserts = Enum.map(st.upsert, &upsert(&1, t, ctx))
    conflict = if st.conflict == :abort, do: nil, else: st.conflict

    {db, n, out, last} =
      Enum.reduce(rows, {db, 0, [], nil}, fn values, {db, n, out, last} ->
        t = db.tables[tkey]

        row =
          Enum.zip(targets, values)
          |> Enum.reduce(defaults(t, targets, ctx), fn {i, v}, r -> put_elem(r, i, v) end)
          |> then(&Row.affinity(t, &1))

        case one(db, t, row, conflict, upserts, ctx) do
          :skip -> {db, n, out, last}
          {:inserted, db, rowid, row} -> {db, n + 1, [Row.returned(ret, rowid, row) | out], rowid}
          {:updated, db, rowid, row} -> {db, n + 1, [Row.returned(ret, rowid, row) | out], last}
        end
      end)

    db = if last, do: %{db | last_rowid: last}, else: db
    {db, n, {Row.names(ret), if(ret, do: Enum.reverse(out), else: [])}}
  end

  # the columns the values go to, by position
  defp targets(t, nil), do: Enum.to_list(0..(length(t.cols) - 1))

  defp targets(t, cols) do
    Enum.map(cols, fn c ->
      case Table.col_index(t, String.downcase(c)) do
        i when is_integer(i) -> i
        :rowid when t.alias != nil -> t.alias
        _ -> Ops.fail("table #{t.name} has no column named #{c}")
      end
    end)
  end

  defp source_rows(%{source: :default}, _t, _targets, _ctx), do: [[]]

  defp source_rows(%{source: {:values, rows}} = st, t, targets, ctx) do
    s = %{id: make_ref(), sources: [], outer: nil, aliases: %{}, agg: nil, ctx: ctx}
    env = %{rows: {}, outer: nil, aggs: nil}

    Enum.map(rows, fn es ->
      count!(st, t, targets, length(es))
      Enum.map(es, fn e -> elem(Compile.expr(e, s), 0).(env) end)
    end)
  end

  defp source_rows(%{source: {:select, sel}} = st, t, targets, ctx) do
    plan = Select.compile(sel, ctx, nil, make_ref())
    count!(st, t, targets, length(plan.names))
    elem(plan.run.(nil), 1)
  end

  defp count!(st, t, targets, n) do
    cond do
      n == length(targets) ->
        :ok

      st.cols == nil ->
        Ops.fail("table #{t.name} has #{length(t.cols)} columns but #{n} values were supplied")

      true ->
        Ops.fail("#{n} values for #{length(targets)} columns")
    end
  end

  defp defaults(t, targets, ctx) do
    t.cols
    |> Enum.with_index()
    |> Enum.map(fn {c, i} -> if i in targets, do: nil, else: Schema.default(c, ctx) end)
    |> List.to_tuple()
  end

  # one row: its constraints, its conflicts, then the write
  defp one(db, t, row, conflict, upserts, ctx) do
    with {:ok, row} <- Row.check(t, row, conflict, ctx) do
      {rowid, row} = Row.rowid(t, row)

      case Row.conflicts(t, rowid, row, nil) do
        [] ->
          {db, _} = Row.put(db, t, rowid, row)
          {:inserted, db, rowid, row}

        cs ->
          resolve(db, t, rowid, row, cs, conflict, upserts, ctx)
      end
    end
  end

  defp resolve(db, t, rowid, row, cs, conflict, upserts, ctx) do
    case Enum.find_value(upserts, fn u ->
           Enum.find_value(cs, &(matches?(u, &1, t) && {u, &1}))
         end) do
      {u, {_, existing}} ->
        do_upsert(db, t, u, existing, row, ctx)

      nil ->
        {first, _} = hd(cs)

        case Row.resolution(conflict, first) do
          :ignore ->
            :skip

          :replace ->
            {db, t} =
              Enum.reduce(Enum.uniq(Enum.map(cs, &elem(&1, 1))), {db, t}, fn r, {db, t} ->
                Row.delete(db, t, r)
              end)

            case Row.conflicts(t, rowid, row, nil) do
              [] -> {:inserted, elem(Row.put(db, t, rowid, row), 0), rowid, row}
              [{c, _} | _] -> Ops.fail(Row.message(t, c))
            end

          _ ->
            Ops.fail(Row.message(t, first))
        end
    end
  end

  defp matches?(%{target: nil}, _, _), do: true
  defp matches?(%{target: cols}, {:rowid, _}, t), do: t.alias != nil and cols == [t.alias]

  defp matches?(%{target: cols}, {ix, _}, _),
    do: Enum.sort(cols) == Enum.sort(Enum.map(ix.cols, &elem(&1, 0)))

  defp do_upsert(_db, _t, %{action: :nothing}, _existing, _row, _ctx), do: :skip

  defp do_upsert(db, t, %{action: {:update, sets, where}}, existing, proposed, ctx) do
    old = Table.get(t, existing)
    env = %{rows: {{existing, old}, {nil, proposed}}, outer: nil, aggs: nil}

    if where == nil or Moss.Sql.Value.truth(where.(env)) == true do
      new = Enum.reduce(sets, old, fn {i, f}, r -> put_elem(r, i, f.(env)) end)
      {db, rowid, row} = Change.write(db, t, existing, old, new, nil, ctx)
      {:updated, db, rowid, row}
    else
      :skip
    end
  end

  defp upsert(u, t, ctx) do
    target =
      u.target &&
        Enum.map(u.target, fn c ->
          case Table.col_index(t, String.downcase(c)) do
            i when is_integer(i) -> i
            :rowid -> t.alias
            nil -> Ops.fail("no such column: #{c}")
          end
        end)

    if target != nil and not target_ok?(t, target),
      do: Ops.fail("ON CONFLICT clause does not match any PRIMARY KEY or UNIQUE constraint")

    excluded = %{
      key: "excluded",
      kind: :table,
      cols: t.cols,
      rowid: true,
      table: t,
      join: :cross,
      on: nil,
      using: nil,
      hidden: Enum.map(t.cols, & &1.key)
    }

    s = Row.scope(t, nil, ctx, [excluded])

    action =
      case u.action do
        :nothing ->
          :nothing

        {:update, sets, where} ->
          fs = Enum.map(sets, fn {c, e} -> {set_col(t, c), elem(Compile.expr(e, s), 0)} end)
          {:update, fs, where && elem(Compile.expr(where, s), 0)}
      end

    %{target: target, action: action}
  end

  defp target_ok?(t, target) do
    (t.alias != nil and target == [t.alias]) or
      Enum.any?(
        t.indexes,
        &(&1.unique and Enum.sort(Enum.map(&1.cols, fn {i, _} -> i end)) == Enum.sort(target))
      )
  end

  def set_col(t, c) do
    case Table.col_index(t, String.downcase(c)) do
      i when is_integer(i) -> i
      :rowid when t.alias != nil -> t.alias
      _ -> Ops.fail("no such column: #{c}")
    end
  end
end

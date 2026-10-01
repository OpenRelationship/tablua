defmodule Moss.Sql.Change do
  @moduledoc """
  UPDATE [OR IGNORE|REPLACE] ... SET ... [WHERE] and DELETE ... [WHERE],
  both with RETURNING. The rows are found as a SELECT finds them (the rowid,
  an index, or a scan), from the table as the statement began; each new value
  is computed from the row as it was. Gives `{db, changes, returned rows}`.
  """
  alias Moss.Sql.{Insert, Ops, Row, Scan, Table, Compile}

  def update(db, st, ctx) do
    t = table(db, st.table)
    s = Row.scope(t, st.as, ctx)
    sets = Enum.map(st.sets, fn {c, e} -> {Insert.set_col(t, c), elem(Compile.expr(e, s), 0)} end)
    ret = Row.returning(st.returning, t, s)
    conflict = if st.conflict == :abort, do: nil, else: st.conflict
    found = found(s, st.where)

    {db, n, out} =
      Enum.reduce(found, {db, 0, []}, fn {rowid, old}, {db, n, out} ->
        t = db.tables[t.key]

        case Table.get(t, rowid) do
          nil ->
            {db, n, out}

          _ ->
            env = %{rows: {{rowid, old}}, outer: nil, aggs: nil}
            new = Enum.reduce(sets, old, fn {i, f}, r -> put_elem(r, i, f.(env)) end)

            case write(db, t, rowid, old, new, conflict, ctx) do
              :skip -> {db, n, out}
              {db, r, row} -> {db, n + 1, [Row.returned(ret, r, row) | out]}
            end
        end
      end)

    {db, n, {Row.names(ret), if(ret, do: Enum.reverse(out), else: [])}}
  end

  @doc "Writes a changed row under the table's constraints: `{db, rowid, row}` or `:skip`."
  def write(db, t, rowid, _old, new, conflict, ctx) do
    new = Row.affinity(t, new)

    case Row.check(t, new, conflict, ctx) do
      :skip ->
        :skip

      {:ok, new} ->
        to =
          case t.alias && elem(new, t.alias) do
            nil when t.alias != nil -> Ops.fail("datatype mismatch")
            nil -> rowid
            v when is_integer(v) -> v
            _ -> Ops.fail("datatype mismatch")
          end

        case Row.conflicts(t, to, new, rowid) do
          [] ->
            {db, _} = Row.put(db, t, to, new, rowid)
            {db, to, new}

          [{c, _} | _] = cs ->
            case Row.resolution(conflict, c) do
              :ignore ->
                :skip

              :replace ->
                {db, t} =
                  cs
                  |> Enum.map(&elem(&1, 1))
                  |> Enum.uniq()
                  |> Enum.reject(&(&1 == rowid))
                  |> Enum.reduce({db, t}, fn r, {db, t} -> Row.delete(db, t, r) end)

                {db, _} = Row.put(db, t, to, new, rowid)
                {db, to, new}

              _ ->
                Ops.fail(Row.message(t, c))
            end
        end
    end
  end

  def delete(db, st, ctx) do
    t = table(db, st.table)
    s = Row.scope(t, st.as, ctx)
    ret = Row.returning(st.returning, t, s)

    {db, n, out} =
      Enum.reduce(found(s, st.where), {db, 0, []}, fn {rowid, row}, {db, n, out} ->
        {db, _} = Row.delete(db, db.tables[t.key], rowid)
        {db, n + 1, [Row.returned(ret, rowid, row) | out]}
      end)

    {db, n, {Row.names(ret), if(ret, do: Enum.reverse(out), else: [])}}
  end

  defp table(db, name) do
    key = String.downcase(name)

    if key in ["sqlite_master", "sqlite_schema"],
      do: Ops.fail("table #{name} may not be modified")

    db.tables[key] || Ops.fail("no such table: #{name}")
  end

  # the rows WHERE picks, as `{rowid, row}`
  defp found(s, where) do
    plan = Scan.plan(s.sources, where, s)
    plan.(nil) |> Enum.map(&elem(&1, 0))
  end
end

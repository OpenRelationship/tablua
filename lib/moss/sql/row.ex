defmodule Moss.Sql.Row do
  @moduledoc """
  What every write does to a row, as SQLite does it: column affinity, NOT
  NULL, CHECK and UNIQUE (the rowid's and each unique index's), each with
  its conflict resolution (ABORT, IGNORE or REPLACE, from the statement or,
  failing that, the constraint), and RETURNING. A database records the rows
  it changed (`dirty`) so `Moss.Sql.Store` writes only those.
  """
  alias Moss.Sql.{Budget, Compile, Ops, Schema, Table, Value}

  @doc "A scope with the one table a write reads (and `excluded`, for an upsert)."
  def scope(t, as, ctx, extra \\ []) do
    src = %{
      key: String.downcase(as || t.name),
      kind: :table,
      cols: t.cols,
      rowid: true,
      table: t,
      join: :first,
      on: nil,
      using: nil,
      hidden: []
    }

    %{id: make_ref(), sources: [src | extra], outer: nil, aliases: %{}, agg: nil, ctx: ctx}
  end

  @doc "Applies each column's affinity."
  def affinity(t, row) do
    t.cols
    |> Enum.with_index()
    |> Enum.reduce(row, fn {c, i}, r ->
      put_elem(r, i, Value.apply_affinity(elem(r, i), c.aff))
    end)
  end

  @doc """
  NOT NULL and CHECK for a row about to be written: `{:ok, row}`, or
  `:skip` when the statement's OR IGNORE says to leave it.
  """
  def check(t, row, conflict, ctx) do
    row =
      t.cols
      |> Enum.with_index()
      |> Enum.reduce_while(row, fn {c, i}, r ->
        if c.notnull && elem(r, i) == nil && i != t.alias do
          case conflict || c.notnull do
            :ignore ->
              {:halt, :skip}

            :replace ->
              case Schema.default(c, ctx) do
                nil -> Ops.fail("NOT NULL constraint failed: #{t.name}.#{c.name}")
                d -> {:cont, put_elem(r, i, Value.apply_affinity(d, c.aff))}
              end

            _ ->
              Ops.fail("NOT NULL constraint failed: #{t.name}.#{c.name}")
          end
        else
          {:cont, r}
        end
      end)

    case row do
      :skip -> :skip
      row -> checks(t, row, conflict, ctx)
    end
  end

  defp checks(%{checks: []}, row, _, _), do: {:ok, row}

  defp checks(t, row, conflict, ctx) do
    s = scope(t, nil, ctx)
    env = %{rows: {{nil, row}}, outer: nil, aggs: nil}

    failed =
      Enum.find(t.checks, fn c ->
        {f, _, _} = Compile.expr(c.expr, s)
        Value.truth(f.(env)) == false
      end)

    cond do
      failed == nil -> {:ok, row}
      conflict == :ignore -> :skip
      true -> Ops.fail("CHECK constraint failed: #{failed.text}")
    end
  end

  @doc "The rowid a row's INTEGER PRIMARY KEY gives, or a new one."
  def rowid(t, row) do
    case t.alias && elem(row, t.alias) do
      nil ->
        r = Table.next_rowid(t)
        {r, if(t.alias, do: put_elem(row, t.alias, r), else: row)}

      v when is_integer(v) ->
        {v, row}

      _ ->
        Ops.fail("datatype mismatch")
    end
  end

  @doc """
  The constraints a row (at `rowid`, replacing `self`) would break:
  `[{index | :rowid, rowid}]`, the rowid's first.
  """
  def conflicts(t, rowid, row, self) do
    by_rowid = if rowid != self and Table.get(t, rowid) != nil, do: [{:rowid, rowid}], else: []
    by_rowid ++ Table.conflicts(t, row, self)
  end

  def message(t, :rowid) do
    col = if t.alias, do: Enum.at(t.cols, t.alias).name, else: "rowid"
    "UNIQUE constraint failed: #{t.name}.#{col}"
  end

  def message(t, ix), do: "UNIQUE constraint failed: " <> Table.index_cols(t, ix)

  @doc "How a conflict resolves: the statement's own clause, else the constraint's, else ABORT."
  def resolution(conflict, :rowid), do: conflict || :abort
  def resolution(conflict, ix), do: conflict || ix.conflict || :abort

  @doc "Writes a row, recording it for the store; `old` is the rowid it had, if it moved."
  def put(db, t, rowid, row, old \\ nil) do
    Budget.spend(1)
    t = if old != nil and old != rowid, do: Table.delete(t, old), else: t
    t = Table.put(t, rowid, row)
    dirty = MapSet.put(db.dirty, {t.key, rowid})
    dirty = if old != nil, do: MapSet.put(dirty, {t.key, old}), else: dirty
    {%{db | tables: Map.put(db.tables, t.key, t), dirty: dirty}, t}
  end

  def delete(db, t, rowid) do
    Budget.spend(1)
    t = Table.delete(t, rowid)
    {%{db | tables: Map.put(db.tables, t.key, t), dirty: MapSet.put(db.dirty, {t.key, rowid})}, t}
  end

  @doc "RETURNING: the compiled columns and their names, or nil."
  def returning(nil, _t, _s), do: nil

  def returning(cols, t, s) do
    Enum.flat_map(cols, fn
      :star ->
        t.cols
        |> Enum.with_index()
        |> Enum.map(fn {c, i} -> {elem(Compile.expr({:ref, 0, i}, s), 0), c.name} end)

      {:expr, e, as, text} ->
        name =
          case {as, e} do
            {nil, {:col, _, n}} -> n
            {nil, _} -> text
            {a, _} -> a
          end

        [{elem(Compile.expr(e, s), 0), name}]
    end)
  end

  def returned(nil, _rowid, _row), do: nil

  def returned(cs, rowid, row),
    do: Enum.map(cs, fn {f, _} -> f.(%{rows: {{rowid, row}}, outer: nil, aggs: nil}) end)

  def names(nil), do: []
  def names(cs), do: Enum.map(cs, &elem(&1, 1))
end

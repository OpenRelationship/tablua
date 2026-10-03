defmodule Moss.Sql.Engine do
  @moduledoc """
  The agent's database, run in Elixir: `exec/4` parses SQL (`Moss.Sql.Parser`)
  and runs each statement against the database held in memory, a statement
  at a time and all or nothing (a failing statement leaves the database as
  it was). Outside BEGIN, each statement's changes go to `flush` as it ends;
  inside, at COMMIT; ROLLBACK goes back to BEGIN. A database is at most
  #{div(64 * 1024 * 1024, 1_048_576)} MB.

      db = Engine.new()
      {:ok, db, %{names: names, rows: rows, changes: n}} = Engine.exec(db, sql, params, flush)

  `flush` is `fn db -> :ok | {:error, why} end`; the rows it must write are
  `db.dirty`, the tables dropped `db.dropped`, and `db.schema` says the schema
  changed.
  """
  alias Moss.Sql.{Budget, Change, Insert, Parser, Row, Schema, Select, Table}

  @max_bytes 64 * 1024 * 1024

  def new do
    %{
      tables: %{},
      owner: %{},
      order: [],
      tx: nil,
      dirty: MapSet.new(),
      dropped: MapSet.new(),
      schema: false,
      last_rowid: 0,
      changes: 0,
      total_changes: 0
    }
  end

  @doc "The database with every table's rows gone and its tables, indexes and schema kept."
  def clear_rows(db) do
    tables =
      Map.new(db.tables, fn {name, t} ->
        indexes = Enum.map(t.indexes, &%{&1 | tree: :gb_sets.empty()})
        {name, %{t | rows: :gb_trees.empty(), size: 0, seq: 0, indexes: indexes}}
      end)

    %{db | tables: tables, last_rowid: 0}
  end

  @doc "Whether the database has nothing left to write."
  def clean?(db),
    do: MapSet.size(db.dirty) == 0 and MapSet.size(db.dropped) == 0 and not db.schema

  def written(db), do: %{db | dirty: MapSet.new(), dropped: MapSet.new(), schema: false}

  def exec(db, sql, params, flush) do
    with {:ok, sts} <- Parser.parse(to_string(sql)),
         {:ok, params} <- params(params),
         :ok <- count(sts, params) do
      run(sts, db, List.to_tuple(params), flush, %{names: [], rows: [], changes: db.changes})
    else
      {:error, why} -> {:error, db, why}
    end
  end

  defp run([], db, _p, _flush, last), do: {:ok, db, last}

  defp run([{st, _} | rest], db, params, flush, _last) do
    Process.put(:sql_cache, %{})
    Process.put(:sql_corr, MapSet.new())

    ctx = %{
      db: db,
      params: params,
      now: System.os_time(:millisecond),
      changes: db.changes,
      last_rowid: db.last_rowid,
      total_changes: db.total_changes
    }

    try do
      {db2, result} = statement(st, db, ctx)
      size = db2.tables |> Map.values() |> Enum.reduce(0, &(&1.size + &2))
      if size > @max_bytes, do: throw({:sql_error, "database or disk is full"})

      case settle(db2, flush) do
        {:ok, db3} -> run(rest, db3, params, flush, result)
        {:error, why} -> {:error, db, why}
      end
    rescue
      e -> {:error, db, "the statement failed: " <> Exception.message(e)}
    catch
      {:sql_error, why} -> {:error, db, why}
    after
      Process.delete(:sql_cache)
      Process.delete(:sql_corr)
      Process.delete(:sql_refs)
    end
  end

  # outside a transaction, a statement's changes are written as it ends
  defp settle(%{tx: nil} = db, flush) do
    if clean?(db) do
      {:ok, db}
    else
      case flush.(db) do
        :ok -> {:ok, written(db)}
        {:error, why} -> {:error, why}
      end
    end
  end

  defp settle(db, _flush), do: {:ok, db}

  defp statement({:select, s}, db, ctx) do
    plan = Select.compile(s, ctx, nil, make_ref())
    {names, rows} = plan.run.(nil)
    Budget.spend(length(rows))
    {db, %{names: names, rows: rows, changes: db.changes}}
  end

  defp statement({kind, st}, db, ctx) when kind in [:insert, :update, :delete] do
    {db, n, {names, rows}} =
      case kind do
        :insert -> Insert.run(db, st, ctx)
        :update -> Change.update(db, st, ctx)
        :delete -> Change.delete(db, st, ctx)
      end

    db = %{db | changes: n, total_changes: db.total_changes + n}
    {db, %{names: names, rows: rows, changes: n}}
  end

  defp statement({:create_table_as, st}, db, ctx) do
    if st.if_not_exists and Map.has_key?(db.tables, String.downcase(st.name)) do
      done(db)
    else
      plan = Select.compile(st.select, ctx, nil, make_ref())
      {names, rows} = plan.run.(nil)
      db = Schema.create_table(db, Schema.as_table(st.name, names, plan.affs))
      key = String.downcase(st.name)

      db =
        rows
        |> Enum.with_index(1)
        |> Enum.reduce(db, fn {vals, rowid}, db ->
          t = db.tables[key]
          elem(Row.put(db, t, rowid, Row.affinity(t, List.to_tuple(vals))), 0)
        end)

      done(db)
    end
  end

  defp statement({:create_table, st}, db, _), do: done(Schema.create_table(db, st))
  defp statement({:create_index, st}, db, _), do: done(Schema.create_index(db, st))
  defp statement({:drop_table, st}, db, _), do: done(Schema.drop_table(db, st))
  defp statement({:drop_index, st}, db, _), do: done(Schema.drop_index(db, st))
  defp statement({:alter_add, st}, db, ctx), do: done(Schema.alter_add(db, st, ctx))

  defp statement({:begin}, %{tx: nil} = db, _), do: done(%{db | tx: db})

  defp statement({:begin}, _db, _),
    do: throw({:sql_error, "cannot start a transaction within a transaction"})

  defp statement({:commit}, %{tx: nil}, _),
    do: throw({:sql_error, "cannot commit - no transaction is active"})

  defp statement({:commit}, db, _), do: done(%{db | tx: nil})

  defp statement({:rollback}, %{tx: nil}, _),
    do: throw({:sql_error, "cannot rollback - no transaction is active"})

  defp statement({:rollback}, %{tx: before} = db, _),
    do:
      done(%{
        before
        | changes: db.changes,
          total_changes: db.total_changes,
          last_rowid: db.last_rowid
      })

  defp done(db), do: {db, %{names: [], rows: [], changes: db.changes}}

  @doc "Ends an open transaction without its changes (a database closed in the middle of one)."
  def rollback(%{tx: nil} = db), do: db
  def rollback(%{tx: before}), do: before

  # Lua's values as SQL's: nil and false are NULL, true is 1, a whole float an integer
  defp params(ps) do
    Enum.reduce_while(ps, {:ok, []}, fn p, {:ok, acc} ->
      case param(p) do
        {:ok, v} -> {:cont, {:ok, [v | acc]}}
        :error -> {:halt, {:error, "a parameter must be a string, a number, a boolean or nil"}}
      end
    end)
    |> case do
      {:ok, acc} -> {:ok, Enum.reverse(acc)}
      e -> e
    end
  end

  defp param(nil), do: {:ok, nil}
  defp param(false), do: {:ok, nil}
  defp param(true), do: {:ok, 1}
  defp param(v) when is_integer(v), do: {:ok, v}

  defp param(v) when is_float(v) do
    if v == trunc(v) and abs(v) < 9_007_199_254_740_992, do: {:ok, trunc(v)}, else: {:ok, v}
  end

  defp param(v) when is_binary(v), do: {:ok, v}
  defp param(_), do: :error

  defp count(sts, params) do
    want = sts |> Enum.map(&elem(&1, 1)) |> Enum.max(fn -> 0 end)

    cond do
      length(params) == want -> :ok
      want == 0 -> {:error, "#{length(params)} values given, but the SQL has no ? parameters"}
      true -> {:error, "#{length(params)} values given for #{want} parameters"}
    end
  end

  @doc "The tables and their row counts, for `cat`."
  def summary(db) do
    db.order
    |> Enum.flat_map(fn
      {:table, k} -> [{db.tables[k].name, Table.count(db.tables[k])}]
      _ -> []
    end)
  end
end

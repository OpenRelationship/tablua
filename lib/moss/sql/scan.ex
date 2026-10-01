defmodule Moss.Sql.Scan do
  @moduledoc """
  FROM and WHERE: the sources a query reads (tables, `sqlite_master`, and
  subqueries), and the nested loop that joins them. Each WHERE (and ON) term
  is checked at the first source where everything it reads is bound; a
  source is read through the rowid, an index's leading columns (`=`, IN, a
  range) or a scan, chosen from those terms. A LEFT JOIN's source gives a
  row of NULLs when no row meets its ON. Every row visited is counted
  (`Moss.Sql.Budget`).
  """
  alias Moss.Sql.{Budget, Compile, Ops, Schema, Select, Table, Value}

  @doc "The sources of FROM as the compiler sees them."
  def sources(from, ctx) do
    Enum.map(from, fn item ->
      {src, key} =
        case item.source do
          {:table, name} -> table_source(name, ctx)
          {:select, s} -> derived(s, ctx)
        end

      Map.merge(src, %{
        key: String.downcase(item.as || key),
        join: item.join,
        on: item.on,
        using: item.using,
        hidden: []
      })
    end)
    |> using()
  end

  defp table_source(name, ctx) do
    key = String.downcase(name)

    cond do
      key in ["sqlite_master", "sqlite_schema"] ->
        rows = Schema.master_rows(ctx.db)

        cols =
          Enum.map(
            ~w(type name tbl_name rootpage sql),
            &%{name: &1, key: &1, aff: nil, coll: nil}
          )

        {%{kind: {:rows, fn _ -> rows end}, cols: cols, rowid: false, table: nil}, name}

      t = ctx.db.tables[key] ->
        {%{kind: :table, cols: t.cols, rowid: true, table: t}, t.name}

      true ->
        throw({:sql_error, "no such table: #{name}"})
    end
  end

  defp derived(s, ctx) do
    plan = Select.compile(s, ctx, nil, make_ref())

    cols =
      Enum.zip([plan.names, plan.affs, plan.colls])
      |> Enum.map(fn {n, a, c} ->
        %{name: n, key: String.downcase(n), aff: a, coll: Compile.coll_of(c)}
      end)
      |> Enum.map(&if(&1.coll == :binary, do: %{&1 | coll: nil}, else: &1))

    run = fn env -> elem(plan.run.(env), 1) end
    {%{kind: {:rows, run}, cols: cols, rowid: false, table: nil}, "subquery"}
  end

  # USING (a, b): the right side's columns hidden from unqualified names and `*`, and the equality added to ON
  defp using(srcs) do
    srcs
    |> Enum.with_index()
    |> Enum.map(fn
      {%{using: nil} = src, _} ->
        src

      {src, j} ->
        eqs =
          Enum.map(src.using, fn name ->
            k = String.downcase(name)
            cj = Enum.find_index(src.cols, &(&1.key == k))

            left =
              srcs
              |> Enum.take(j)
              |> Enum.with_index()
              |> Enum.find_value(fn {l, i} ->
                ci = Enum.find_index(l.cols, &(&1.key == k))
                ci && {i, ci}
              end)

            if cj == nil or left == nil,
              do:
                throw(
                  {:sql_error,
                   "cannot join using column #{name} - column not present in both tables"}
                )

            {:bin, "=", {:ref, elem(left, 0), elem(left, 1)}, {:ref, j, cj}}
          end)

        on = Enum.reduce(eqs ++ List.wrap(src.on), fn e, acc -> {:and, acc, e} end)
        %{src | on: on, hidden: Enum.map(src.using, &String.downcase/1)}
    end)
  end

  @doc """
  The join's plan: a function from the outer environment to the list of
  joined rows (a tuple, one `{rowid, values}` per source).
  """
  def plan(srcs, where, scope) do
    n = length(srcs)

    left_on =
      for {src, j} <- Enum.with_index(srcs),
          src.join == :left,
          into: %{},
          do: {j, conjuncts(src.on)}

    pool =
      conjuncts(where) ++
        Enum.flat_map(srcs, fn src -> if src.join == :left, do: [], else: conjuncts(src.on) end)

    pool = Enum.map(pool, &{&1, Compile.with_refs(&1, scope)})
    level = fn refs -> if MapSet.size(refs) == 0, do: 0, else: Enum.max(refs) end
    by_level = Enum.group_by(pool, fn {_, {_, refs}} -> level.(refs) end)

    levels =
      for {src, j} <- Enum.with_index(srcs) do
        where_j = Map.get(by_level, j, [])
        on_j = Enum.map(Map.get(left_on, j, []), &{&1, Compile.with_refs(&1, scope)})
        usable = if src.join == :left, do: on_j, else: where_j

        %{
          src: src,
          left: src.join == :left,
          on: Enum.map(on_j, fn {_, {{f, _, _}, _}} -> f end),
          where: Enum.map(where_j, fn {_, {{f, _, _}, _}} -> f end),
          access: access(src, j, usable, scope),
          width: length(src.cols)
        }
      end
      |> List.to_tuple()

    empty = List.to_tuple(List.duplicate(nil, n))

    if n == 0 do
      conds = Enum.map(pool, fn {_, {{f, _, _}, _}} -> f end)

      fn outer ->
        env = %{rows: {}, outer: outer, aggs: nil}
        if Enum.all?(conds, &(Value.truth(&1.(env)) == true)), do: [{}], else: []
      end
    else
      fn outer ->
        prepared = prepare(levels, outer)
        loop(prepared, 0, n, empty, outer, []) |> Enum.reverse()
      end
    end
  end

  def conjuncts(nil), do: []
  def conjuncts({:and, a, b}), do: conjuncts(a) ++ conjuncts(b)
  def conjuncts(e), do: [e]

  # a source whose rows come from a subquery is read once for each run of the plan
  defp prepare(levels, outer) do
    levels
    |> Tuple.to_list()
    |> Enum.map(fn
      %{src: %{kind: {:rows, run}}} = l ->
        rows = run.(%{rows: {}, outer: outer, aggs: nil})
        %{l | access: {:list, Enum.map(rows, &{nil, List.to_tuple(&1)})}}

      l ->
        l
    end)
    |> List.to_tuple()
  end

  defp loop(_levels, j, n, rows, _outer, acc) when j == n, do: [rows | acc]

  defp loop(levels, j, n, rows, outer, acc) do
    l = elem(levels, j)
    cands = candidates(l, %{rows: rows, outer: outer, aggs: nil})

    {acc, matched} =
      Enum.reduce(cands, {acc, false}, fn row, {acc, matched} ->
        Budget.spend(1)
        rows = put_elem(rows, j, row)
        env = %{rows: rows, outer: outer, aggs: nil}

        if all?(l.on, env) do
          if all?(l.where, env),
            do: {loop(levels, j + 1, n, rows, outer, acc), true},
            else: {acc, true}
        else
          {acc, matched}
        end
      end)

    if l.left and not matched do
      rows = put_elem(rows, j, {nil, List.to_tuple(List.duplicate(nil, l.width))})
      env = %{rows: rows, outer: outer, aggs: nil}
      if all?(l.where, env), do: loop(levels, j + 1, n, rows, outer, acc), else: acc
    else
      acc
    end
  end

  defp all?([], _env), do: true
  defp all?([f | fs], env), do: Value.truth(f.(env)) == true and all?(fs, env)

  # -- access paths ------------------------------------------------------------------------------

  defp candidates(%{access: {:list, rows}}, _env), do: rows
  defp candidates(%{access: :scan, src: src}, _env), do: :gb_trees.to_list(src.table.rows)

  defp candidates(%{access: {:rowid, probes}, src: src}, env) do
    probes
    |> Enum.map(fn {f, conv} -> rowid(Ops.prep(f.(env), conv)) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.flat_map(fn r -> ((row = Table.get(src.table, r)) && [{r, row}]) || [] end)
  end

  defp candidates(%{access: {:index, ix, probes}, src: src}, env) do
    keys =
      Enum.zip_with(probes, ix.cols, fn {f, conv}, {_, coll} ->
        key(Ops.prep(f.(env), conv), coll)
      end)

    if Enum.member?(keys, nil),
      do: [],
      else: Table.eq(ix, keys) |> rows(src.table)
  end

  defp candidates(%{access: {:index_in, ix, probes}, src: src}, env) do
    {_, coll} = hd(ix.cols)

    probes
    |> Enum.map(fn {f, conv} -> key(Ops.prep(f.(env), conv), coll) end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.flat_map(&Table.eq(ix, [&1]))
    |> Enum.uniq()
    |> rows(src.table)
  end

  defp candidates(%{access: {:range, ix, lo, hi}, src: src} = l, env) do
    coll = if ix == :rowid, do: :binary, else: elem(hd(ix.cols), 1)
    lo = bound(lo, coll, env)
    hi = bound(hi, coll, env)

    cond do
      lo == :null or hi == :null -> []
      ix == :rowid -> rowid_range(src.table, lo, hi, l)
      true -> Table.range(ix, lo, hi) |> rows(src.table)
    end
  end

  defp rows(rowids, t), do: Enum.map(rowids, &{&1, Table.get(t, &1)})

  defp key(nil, _), do: nil
  defp key(v, coll), do: Value.key(v, coll)

  defp bound(nil, _, _), do: nil

  defp bound({f, conv, incl}, coll, env) do
    case Ops.prep(f.(env), conv) do
      nil -> :null
      v -> {Value.key(v, coll), incl}
    end
  end

  defp rowid(v) when is_integer(v), do: v
  defp rowid(v) when is_float(v) and v == trunc(v), do: trunc(v)
  defp rowid(_), do: nil

  # a rowid range over numbers; a bound that is text or a blob is past every rowid, so a scan answers it
  defp rowid_range(t, lo, hi, _l) do
    numeric = fn
      nil -> true
      {{1, _}, _} -> true
      _ -> false
    end

    if numeric.(lo) and numeric.(hi) do
      start =
        case lo do
          nil -> Value.min_int() - 1
          {{1, v}, _} -> if is_float(v), do: floor(v), else: v
        end

      iter = :gb_trees.iterator_from(start, t.rows)
      take_rowids(iter, lo, hi, [])
    else
      :gb_trees.to_list(t.rows)
    end
  end

  defp take_rowids(iter, lo, hi, acc) do
    case :gb_trees.next(iter) do
      {r, row, iter} ->
        cond do
          lo != nil and not above(r, lo) -> take_rowids(iter, lo, hi, acc)
          hi == nil or below(r, hi) -> take_rowids(iter, lo, hi, [{r, row} | acc])
          true -> Enum.reverse(acc)
        end

      :none ->
        Enum.reverse(acc)
    end
  end

  defp above(r, {{1, v}, true}), do: r >= v
  defp above(r, {{1, v}, false}), do: r > v
  defp below(r, {{1, v}, true}), do: r <= v
  defp below(r, {{1, v}, false}), do: r < v
  defp below(_r, {{_, _}, _}), do: true

  # The best way in to source j from the terms that can use it: the rowid, then an index's equality (the
  # longest prefix), IN, then a range; a scan otherwise.
  defp access(%{kind: {:rows, _}}, _j, _terms, _scope), do: :rows

  defp access(%{kind: :table, table: t}, j, terms, scope),
    do: Moss.Sql.Plan.choose(t, j, terms, scope)
end

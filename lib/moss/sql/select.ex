defmodule Moss.Sql.Select do
  @moduledoc """
  A SELECT compiled to a plan: `%{run, names, affs, colls}`, where `run`
  takes the outer row environment (nil at the top) and gives `{names,
  rows}`, each row a list of values. The rows come from `Moss.Sql.Scan`;
  then GROUP BY and the aggregates (`Moss.Sql.Aggregate`), HAVING, the
  result columns, DISTINCT, ORDER BY (NULLs first ascending, as SQLite) and
  LIMIT/OFFSET. Compound selects (UNION [ALL], INTERSECT, EXCEPT) give their
  rows in SQLite's order, sorted unless UNION ALL.
  """
  alias Moss.Sql.{Aggregate, Budget, Compile, Scan, Sort, Value}

  def compile(sel, ctx, outer, id) do
    case sel.cores do
      [{nil, core}] ->
        single(core, sel, ctx, outer, id)

      [{nil, first} | more] ->
        compound(first, more, sel, ctx, outer, id)
    end
  end

  # -- one SELECT --------------------------------------------------------------------------------

  defp single(core, sel, ctx, outer, id) do
    srcs = Scan.sources(core.from, ctx)
    cols = expand(core.cols, srcs)

    aliases =
      for {ast, _, true} <- cols, into: %{}, do: {String.downcase(elem(ast, 1)), elem(ast, 0)}

    scope = %{
      id: id,
      sources: srcs,
      outer: outer,
      aliases: aliases,
      agg: nil,
      ctx: ctx,
      groups: []
    }

    slot = {:sql_aggs, id}
    Process.put(slot, [])
    group_asts = Enum.map(core.group, &group_term(&1, cols, aliases, srcs))
    ascope = %{scope | agg: {:collect, slot}, groups: Enum.with_index(group_asts)}

    out = Enum.map(cols, fn {{e, _}, _, _} -> Compile.expr(e, ascope) end)
    names = Enum.map(cols, fn {_, name, _} -> name end)
    having = core.having && elem(Compile.expr(core.having, ascope), 0)
    order = order_terms(sel.order, out, names, ascope)
    aggs = Process.get(slot)
    Process.delete(slot)
    group = Enum.map(group_asts, &Compile.expr(&1, scope))

    if having && aggs == [] && group == [],
      do: throw({:sql_error, "HAVING clause on a non-aggregate query"})

    scan = Scan.plan(srcs, core.where, scope)
    {limit, offset} = limits(sel, ctx)
    distinct = core.distinct
    colls = Enum.map(out, fn {_, _, c} -> c end)
    out_fs = Enum.map(out, &elem(&1, 0))
    grouped = aggs != [] or group != []

    null_rows =
      srcs
      |> Enum.map(&{nil, List.to_tuple(List.duplicate(nil, length(&1.cols)))})
      |> List.to_tuple()

    run = fn outer_env ->
      envs = scan.(outer_env)

      envs =
        if grouped,
          do:
            Aggregate.groups(envs, group, aggs, outer_env, null_rows)
            |> Enum.filter(&(having == nil or Value.truth(having.(&1)) == true)),
          else: Enum.map(envs, &%{rows: &1, outer: outer_env, aggs: nil})

      rows =
        Enum.map(envs, fn env ->
          {Enum.map(out_fs, & &1.(env)), Enum.map(order, fn {f, _, _, _} -> f.(env) end)}
        end)

      rows = if distinct, do: Enum.uniq_by(rows, fn {vs, _} -> keys(vs, colls) end), else: rows
      rows = Sort.sort(rows, order) |> Enum.map(&elem(&1, 0))
      {names, slice(rows, limit, offset)}
    end

    %{run: run, names: names, affs: Enum.map(out, &elem(&1, 1)), colls: colls}
  end

  # GROUP BY 2: the second result column; GROUP BY an alias: its expression
  defp group_term({:lit, k}, cols, _, _) when is_integer(k) do
    if k < 1 or k > length(cols),
      do:
        throw(
          {:sql_error,
           "#{ordinal(k)} GROUP BY term out of range - should be between 1 and #{length(cols)}"}
        )

    {{e, _}, _, _} = Enum.at(cols, k - 1)
    e
  end

  defp group_term({:col, nil, name} = e, _, aliases, srcs) do
    k = String.downcase(name)
    column? = Enum.any?(srcs, fn src -> Enum.any?(src.cols, &(&1.key == k)) end)
    if column?, do: e, else: Map.get(aliases, k, e)
  end

  defp group_term(e, _, _, _), do: e

  # the result columns: `*` and `t.*` as each column of their sources, an expression with its alias or its text
  defp expand(cols, srcs) do
    Enum.flat_map(cols, fn
      :star ->
        if srcs == [], do: throw({:sql_error, "no tables specified"})
        Enum.flat_map(Enum.with_index(srcs), &source_cols/1)

      {:tstar, t} ->
        k = String.downcase(t)

        case Enum.find_index(srcs, &(&1.key == k)) do
          nil -> throw({:sql_error, "no such table: #{t}"})
          j -> source_cols({Enum.at(srcs, j), j})
        end

      {:expr, e, as, text} ->
        name = as || plain_name(e, srcs) || text
        [{{e, name}, name, as != nil}]
    end)
  end

  defp source_cols({src, j}) do
    for {c, ci} <- Enum.with_index(src.cols),
        c.key not in src.hidden,
        do: {{{:ref, j, ci}, c.name}, c.name, false}
  end

  # a bare column takes its declared name, as SQLite names it
  defp plain_name({:col, t, name}, srcs) do
    k = String.downcase(name)
    tk = t && String.downcase(t)
    srcs = Enum.filter(srcs, &(tk == nil or &1.key == tk))

    Enum.find_value(srcs, fn src -> Enum.find_value(src.cols, &(&1.key == k && &1.name)) end) ||
      (k in ["rowid", "oid", "_rowid_"] && Enum.find_value(srcs, &rowid_name/1)) || (t && name)
  end

  defp plain_name(_, _), do: nil

  # rowid names the INTEGER PRIMARY KEY's column, when the table has one
  defp rowid_name(%{table: %{alias: i, cols: cols}}) when is_integer(i), do: Enum.at(cols, i).name
  defp rowid_name(_), do: nil

  # ORDER BY: a number is a result column, a result alias is that column, anything else an expression
  defp order_terms(terms, out, names, scope) do
    Enum.with_index(terms, 1)
    |> Enum.map(fn {{e, dir, nulls}, n} ->
      {f, _, coll} =
        case e do
          {:lit, k} when is_integer(k) ->
            if k < 1 or k > length(out),
              do:
                throw(
                  {:sql_error,
                   "#{ordinal(n)} ORDER BY term out of range - should be between 1 and #{length(out)}"}
                )

            Enum.at(out, k - 1)

          {:col, nil, name} ->
            case Enum.find_index(Map.keys(scope.aliases), &(&1 == String.downcase(name))) do
              nil ->
                Compile.expr(e, scope)

              _ ->
                Enum.at(
                  out,
                  Enum.find_index(names, &(String.downcase(&1) == String.downcase(name)))
                )
            end

          _ ->
            Compile.expr(e, scope)
        end

      {f, dir, nulls, Compile.coll_of(coll)}
    end)
  end

  defp ordinal(1), do: "1st"
  defp ordinal(2), do: "2nd"
  defp ordinal(3), do: "3rd"
  defp ordinal(n), do: "#{n}th"

  defp keys(vs, colls),
    do: Enum.zip_with(vs, colls, fn v, c -> Value.key(v, Compile.coll_of(c)) end)

  # -- LIMIT -------------------------------------------------------------------------------------

  defp limits(sel, ctx) do
    scope = %{id: make_ref(), sources: [], outer: nil, aliases: %{}, agg: nil, ctx: ctx}
    {limit_of(sel.limit, scope), limit_of(sel.offset, scope)}
  end

  defp limit_of(nil, _), do: nil

  defp limit_of(e, scope) do
    {f, _, _} = Compile.expr(e, scope)

    case Value.apply_affinity(f.(%{rows: {}, outer: nil, aggs: nil}), :integer) do
      n when is_integer(n) -> n
      _ -> throw({:sql_error, "datatype mismatch"})
    end
  end

  defp slice(rows, limit, offset) do
    rows = if offset && offset > 0, do: Enum.drop(rows, offset), else: rows
    if limit && limit >= 0, do: Enum.take(rows, limit), else: rows
  end

  # -- compounds ---------------------------------------------------------------------------------

  defp compound(first, more, sel, ctx, outer, id) do
    plans =
      [{nil, first} | more]
      |> Enum.map(fn {op, core} ->
        {op, compile(%{cores: [{nil, core}], order: [], limit: nil, offset: nil}, ctx, outer, id)}
      end)

    [{nil, p0} | _] = plans
    n = length(p0.names)

    for {op, p} <- tl(plans),
        length(p.names) != n,
        do:
          throw(
            {:sql_error,
             "SELECTs to the left and right of #{op_name(op)} do not have the same number of result columns"}
          )

    order = compound_order(sel.order, p0)
    {limit, offset} = limits(sel, ctx)
    colls = p0.colls

    run = fn env ->
      rows =
        Enum.reduce(plans, [], fn {op, p}, acc ->
          {_, rows} = p.run.(env)
          Budget.spend(length(rows))
          combine(op, acc, rows, colls)
        end)

      rows = Enum.map(rows, &{&1, Enum.map(order, fn {i, _, _, _} -> Enum.at(&1, i) end)})
      order_fs = Enum.map(order, fn {_, d, nl, c} -> {nil, d, nl, c} end)
      rows = Sort.sort(rows, order_fs) |> Enum.map(&elem(&1, 0))
      {p0.names, slice(rows, limit, offset)}
    end

    %{run: run, names: p0.names, affs: p0.affs, colls: colls}
  end

  defp op_name(:union_all), do: "UNION ALL"
  defp op_name(op), do: op |> to_string() |> String.upcase()

  defp combine(nil, _acc, rows, _), do: rows
  defp combine(:union_all, acc, rows, _), do: acc ++ rows
  defp combine(:union, acc, rows, colls), do: distinct_sorted(acc ++ rows, colls)

  defp combine(:intersect, acc, rows, colls) do
    have = MapSet.new(rows, &keys(&1, colls))
    acc |> Enum.filter(&MapSet.member?(have, keys(&1, colls))) |> distinct_sorted(colls)
  end

  defp combine(:except, acc, rows, colls) do
    drop = MapSet.new(rows, &keys(&1, colls))
    acc |> Enum.reject(&MapSet.member?(drop, keys(&1, colls))) |> distinct_sorted(colls)
  end

  defp distinct_sorted(rows, colls) do
    rows |> Enum.uniq_by(&keys(&1, colls)) |> Enum.sort_by(&keys(&1, colls))
  end

  defp compound_order(terms, p0) do
    Enum.with_index(terms, 1)
    |> Enum.map(fn {{e, dir, nulls}, n} ->
      i =
        case e do
          {:lit, k} when is_integer(k) and k >= 1 and k <= length(p0.names) ->
            k - 1

          {:col, nil, name} ->
            Enum.find_index(p0.names, &(String.downcase(&1) == String.downcase(name)))

          {:collate, {:col, nil, name}, _} ->
            Enum.find_index(p0.names, &(String.downcase(&1) == String.downcase(name)))

          _ ->
            nil
        end

      if i == nil,
        do:
          throw(
            {:sql_error,
             "#{ordinal(n)} ORDER BY term does not match any column in the result set"}
          )

      coll =
        case e do
          {:collate, _, c} -> Value.collation(c)
          _ -> Compile.coll_of(Enum.at(p0.colls, i))
        end

      {i, dir, nulls, coll}
    end)
  end
end

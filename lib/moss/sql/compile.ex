defmodule Moss.Sql.Compile do
  @moduledoc """
  An expression's tree as an Elixir closure over a row environment
  (`%{rows: {row per source}, outer: env | nil, aggs: tuple | nil}`, a source's
  row `{rowid, values}`), with what comparisons need of it: its affinity and
  its collation (`{:explicit, c}` from COLLATE, `{:col, c}` from a column).

  Names resolve as SQLite resolves them: a column of the FROM sources
  (ambiguous when two have it), then the result's aliases, then an outer
  query's sources (a correlated subquery). Parameters and CURRENT_* are
  fixed when the statement starts. Aggregates register with the select
  being compiled and read their value from `env.aggs`.

  A scope is `%{id, sources, outer, aliases, agg, ctx}`; `ctx` holds the
  parameters, the time, and the database (for subqueries).
  """
  alias Moss.Sql.{Calls, Names, Ops, Select, Value}

  def fail(msg), do: throw({:sql_error, msg})

  @doc """
  Compiles `ast` in `scope`: `{fun, affinity, collation}`. In an aggregate
  query a GROUP BY term (`scope.groups`) reads the group's own value.
  """
  def expr(ast, %{groups: [_ | _] = gs} = s) do
    case List.keyfind(gs, ast, 0) do
      {_, i} ->
        {_, aff, coll} = expr(ast, %{s | groups: []})
        {fn env -> elem(env.gvals, i) end, aff, coll}

      nil ->
        expr_(ast, s)
    end
  end

  def expr(ast, s), do: expr_(ast, s)

  defp expr_({:lit, v}, _s), do: {fn _ -> v end, nil, nil}

  defp expr_({:param, n}, s),
    do:
      (
        v = param(s.ctx, n)
        {fn _ -> v end, nil, nil}
      )

  defp expr_({:now, kind}, s) do
    v = Moss.Sql.Date.now(kind, s.ctx.now)
    {fn _ -> v end, nil, nil}
  end

  defp expr_({:col, t, name}, s), do: column(t, name, s)

  # a source's column by position (`*`, USING), already resolved
  defp expr_({:ref, si, ci}, s) do
    Names.track(s, 0, si)

    col =
      if ci == :rowid,
        do: %{aff: :integer, coll: nil},
        else: Enum.at(Enum.at(s.sources, si).cols, ci)

    {Names.reader(0, si, ci), col.aff, {:col, col.coll || :binary}}
  end

  defp expr_({:collate, e, c}, s) do
    {f, aff, _} = expr(e, s)
    {f, aff, {:explicit, Value.collation(c)}}
  end

  defp expr_({:cast, e, type}, s) do
    {f, _, coll} = expr(e, s)
    {fn env -> Ops.cast(f.(env), type) end, Value.affinity(type), coll}
  end

  defp expr_({:neg, e}, s) do
    {f, _, c} = expr(e, s)
    {fn env -> Ops.neg(f.(env)) end, nil, explicit([c])}
  end

  defp expr_({:bitnot, e}, s) do
    {f, _, c} = expr(e, s)
    {fn env -> Ops.bitnot(f.(env)) end, nil, explicit([c])}
  end

  defp expr_({:not, e}, s) do
    {f, _, c} = expr(e, s)
    {fn env -> Ops.lnot(f.(env)) end, nil, explicit([c])}
  end

  defp expr_({:and, a, b}, s) do
    {fa, _, ca} = expr(a, s)
    {fb, _, cb} = expr(b, s)

    {fn env ->
       case Value.truth(fa.(env)) do
         false -> 0
         ta -> Ops.land(Ops.bool(ta), fb.(env))
       end
     end, nil, explicit([ca, cb])}
  end

  defp expr_({:or, a, b}, s) do
    {fa, _, ca} = expr(a, s)
    {fb, _, cb} = expr(b, s)

    {fn env ->
       case Value.truth(fa.(env)) do
         true -> 1
         ta -> Ops.lor(Ops.bool(ta), fb.(env))
       end
     end, nil, explicit([ca, cb])}
  end

  defp expr_({:bin, op, a, b}, s) when op in ["=", "!=", "<", "<=", ">", ">="] do
    {fa, la, ca} = expr(a, s)
    {fb, ra, cb} = expr(b, s)
    {pa, pb} = Ops.cmp_affinity(la, ra)
    coll = cmp_coll(ca, cb)

    {fn env -> Ops.compare(op, Ops.prep(fa.(env), pa), Ops.prep(fb.(env), pb), coll) end, nil,
     explicit([ca, cb])}
  end

  defp expr_({:bin, op, a, b}, s) do
    {fa, _, ca} = expr(a, s)
    {fb, _, cb} = expr(b, s)

    f =
      case op do
        o when o in ["+", "-", "*", "/", "%"] -> fn env -> Ops.arith(o, fa.(env), fb.(env)) end
        "||" -> fn env -> Ops.concat(fa.(env), fb.(env)) end
        o -> fn env -> Ops.bit(o, fa.(env), fb.(env)) end
      end

    {f, nil, explicit([ca, cb])}
  end

  defp expr_({:is, a, b, neg}, s) do
    {fa, la, ca} = expr(a, s)
    {fb, ra, cb} = expr(b, s)
    {pa, pb} = Ops.cmp_affinity(la, ra)
    coll = cmp_coll(ca, cb)

    {fn env -> Ops.bool(Ops.is(Ops.prep(fa.(env), pa), Ops.prep(fb.(env), pb), coll) != neg) end,
     nil, explicit([ca, cb])}
  end

  defp expr_({:between, e, lo, hi, neg}, s) do
    {f, _, c} = expr({:and, {:bin, ">=", e, lo}, {:bin, "<=", e, hi}}, s)
    if neg, do: {fn env -> Ops.lnot(f.(env)) end, nil, c}, else: {f, nil, c}
  end

  defp expr_({:like, kind, e, p, esc, neg}, s) do
    {fe, _, ce} = expr(e, s)
    {fp, _, cp} = expr(p, s)
    {fesc, _, cesc} = if esc, do: expr(esc, s), else: {fn _ -> nil end, nil, nil}
    c = explicit([ce, cp, cesc])

    f =
      if kind == "like",
        do: fn env -> Ops.like(fe.(env), fp.(env), fesc.(env)) end,
        else: fn env -> Ops.glob(fe.(env), fp.(env)) end

    if neg, do: {fn env -> Ops.lnot(f.(env)) end, nil, c}, else: {f, nil, c}
  end

  defp expr_({:in, e, {:list, items}, neg}, s) do
    {fe, la, ce} = expr(e, s)
    cs = Enum.map(items, &expr(&1, s))

    f = fn env ->
      v = fe.(env)

      Enum.reduce_while(cs, 0, fn {fi, ra, ci}, acc ->
        {pa, pb} = Ops.cmp_affinity(la, ra)

        case Ops.compare("=", Ops.prep(v, pa), Ops.prep(fi.(env), pb), cmp_coll(ce, ci)) do
          1 -> {:halt, 1}
          nil -> {:cont, nil}
          0 -> {:cont, acc}
        end
      end)
      |> then(&if(v == nil and cs != [], do: nil, else: &1))
    end

    {negate(f, neg), nil, explicit([ce | Enum.map(cs, &elem(&1, 2))])}
  end

  defp expr_({:in, e, {:select, sel}, neg}, s) do
    {fe, la, ce} = expr(e, s)
    {run, plan} = subquery(sel, s)

    if length(plan.names) != 1,
      do: fail("sub-select returns #{length(plan.names)} columns - expected 1")

    ra = hd(plan.affs)
    coll = cmp_coll(ce, hd(plan.colls))
    {pa, pb} = Ops.cmp_affinity(la, ra)

    f = fn env ->
      {set, has_null} = run.(env, {:set, pa, pb, coll})
      v = Ops.prep(fe.(env), pa)

      cond do
        map_size(set) == 0 and not has_null -> 0
        v == nil -> nil
        Map.has_key?(set, Value.key(v, coll)) -> 1
        has_null -> nil
        true -> 0
      end
    end

    {negate(f, neg), nil, explicit([ce])}
  end

  defp expr_({:exists, sel}, s) do
    {run, _} = subquery(sel, s)
    {fn env -> Ops.bool(run.(env, :rows) != []) end, nil, nil}
  end

  defp expr_({:subquery, sel}, s) do
    {run, plan} = subquery(sel, s)

    {fn env ->
       case run.(env, :rows) do
         [[v | _] | _] -> v
         _ -> nil
       end
     end, hd(plan.affs), hd(plan.colls)}
  end

  defp expr_({:case, base, whens, else_}, s) do
    fb = if base, do: expr(base, s)
    cw = Enum.map(whens, fn {w, t} -> {expr(w, s), expr(t, s)} end)
    {fe, _, ce} = if else_, do: expr(else_, s), else: {fn _ -> nil end, nil, nil}

    colls =
      [fb && elem(fb, 2)] ++ Enum.flat_map(cw, fn {{_, _, a}, {_, _, b}} -> [a, b] end) ++ [ce]

    cw = Enum.map(cw, fn {w, {ft, _, _}} -> {w, ft} end)

    f = fn env ->
      bv = if fb, do: elem(fb, 0).(env)

      hit =
        Enum.find(cw, fn {{fw, ra, cw_}, _} ->
          if fb do
            {_, la, cb} = fb
            {pa, pb} = Ops.cmp_affinity(la, ra)
            Ops.compare("=", Ops.prep(bv, pa), Ops.prep(fw.(env), pb), cmp_coll(cb, cw_)) == 1
          else
            Value.truth(fw.(env)) == true
          end
        end)

      case hit do
        {_, ft} -> ft.(env)
        nil -> fe.(env)
      end
    end

    {f, nil, explicit(colls)}
  end

  defp expr_({:fn, name, args, distinct}, s), do: Calls.compile(name, args, distinct, s)

  # -- helpers -----------------------------------------------------------------------------------

  defp negate(f, false), do: f
  defp negate(f, true), do: fn env -> Ops.lnot(f.(env)) end

  # SQLite's EP_Collate: an explicit COLLATE anywhere below gives the whole expression its collation, the
  # leftmost first; a column's own collation counts only for the column itself (and through CAST)
  @doc "The first explicit collation among `colls`, if any."
  def explicit(colls), do: Enum.find(colls, &match?({:explicit, _}, &1))

  @doc "The collation a comparison uses: an explicit one (left first), else a column's (left first)."
  def cmp_coll(a, b) do
    case {a, b} do
      {{:explicit, c}, _} -> c
      {_, {:explicit, c}} -> c
      {{:col, c}, _} -> c
      {_, {:col, c}} -> c
      _ -> :binary
    end
  end

  def coll_of({_, c}), do: c
  def coll_of(nil), do: :binary

  defp param(ctx, n) do
    case ctx.params do
      p when n <= tuple_size(p) -> elem(p, n - 1)
      _ -> nil
    end
  end

  # a subquery's plan, its result cached for the statement when it reads nothing of the outer query
  defp subquery(sel, s) do
    id = make_ref()
    plan = Select.compile(sel, s.ctx, s, id)
    correlated = MapSet.member?(Process.get(:sql_corr, MapSet.new()), id)

    run = fn env, kind ->
      if correlated do
        shape(plan.run.(env), kind)
      else
        cache = Process.get(:sql_cache, %{})

        case cache do
          %{{^id, ^kind} => v} ->
            v

          _ ->
            v = shape(plan.run.(env), kind)
            Process.put(:sql_cache, Map.put(cache, {id, kind}, v))
            v
        end
      end
    end

    {run, plan}
  end

  defp shape({_names, rows}, :rows), do: rows

  defp shape({_names, rows}, {:set, _pa, pb, coll}) do
    Enum.reduce(rows, {%{}, false}, fn [v | _], {set, null} ->
      case Ops.prep(v, pb) do
        nil -> {set, true}
        v -> {Map.put(set, Value.key(v, coll), true), null}
      end
    end)
  end

  defp column(t, name, s), do: Names.column(t, name, s)

  defdelegate resolve(s, t, name, d), to: Names
  defdelegate with_refs(ast, s), to: Names
end

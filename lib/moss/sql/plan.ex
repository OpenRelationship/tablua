defmodule Moss.Sql.Plan do
  @moduledoc """
  How a query reaches one table: from the WHERE (or ON) terms that compare
  one of its columns with something already known (a constant, a
  parameter, an earlier table's column), it picks the rowid, the index
  with the longest run of leading `=` columns, an IN list, or a range, and
  otherwise a scan. A term is used only when SQLite's affinity and
  collation rules make the index's order the comparison's own; every term is
  still checked on each row the path gives.
  """
  alias Moss.Sql.{Compile, Ops}

  def choose(t, j, terms, scope) do
    facts = Enum.flat_map(terms, fn {ast, _} -> facts(ast, j, scope) end)
    rowid? = fn ci -> ci == :rowid or (t.alias != nil and ci == t.alias) end
    eq = for {:eq, ci, p, coll} <- facts, do: {ci, p, coll}

    rowid_eq = Enum.find(eq, fn {ci, _, _} -> rowid?.(ci) end)

    best_eq =
      t.indexes
      |> Enum.map(fn ix -> {ix, prefix(ix, eq)} end)
      |> Enum.filter(fn {_, ps} -> ps != [] end)
      |> Enum.max_by(
        fn {ix, ps} -> {length(ps), ix.unique and length(ps) == length(ix.cols)} end,
        fn -> nil end
      )

    ins = for {:in, ci, ps, coll} <- facts, do: {ci, ps, coll}

    cond do
      rowid_eq ->
        {:rowid, [elem(rowid_eq, 1)]}

      best_eq ->
        {ix, ps} = best_eq
        {:index, ix, ps}

      r = Enum.find(ins, fn {ci, _, _} -> rowid?.(ci) end) ->
        {:rowid, elem(r, 1)}

      r = index_in(t, ins) ->
        r

      r = range(facts, rowid?, nil) ->
        r

      r = Enum.find_value(t.indexes, &range(facts, fn ci -> ci == elem(hd(&1.cols), 0) end, &1)) ->
        r

      true ->
        :scan
    end
  end

  defp prefix(ix, eq) do
    Enum.reduce_while(ix.cols, [], fn {ci, coll}, acc ->
      case Enum.find(eq, fn {c, _, cc} -> c == ci and cc == coll end) do
        nil -> {:halt, acc}
        {_, p, _} -> {:cont, acc ++ [p]}
      end
    end)
  end

  defp index_in(t, ins) do
    Enum.find_value(t.indexes, fn ix ->
      {c0, coll} = hd(ix.cols)

      case Enum.find(ins, fn {ci, _, cc} -> ci == c0 and cc == coll end) do
        nil -> nil
        {_, ps, _} -> {:index_in, ix, ps}
      end
    end)
  end

  defp range(facts, col?, ix) do
    coll = if ix, do: elem(hd(ix.cols), 1)
    ok = fn ci, cc -> col?.(ci) and (ix == nil or cc == coll) end

    lo =
      Enum.find_value(facts, fn
        {:lo, ci, p, cc} -> ok.(ci, cc) && p
        _ -> nil
      end)

    hi =
      Enum.find_value(facts, fn
        {:hi, ci, p, cc} -> ok.(ci, cc) && p
        _ -> nil
      end)

    if lo || hi, do: {:range, ix || :rowid, lo, hi}
  end

  # -- what a term says about source j -----------------------------------------------------------

  defp facts({:bin, op, a, b}, j, s) when op in ["=", "<", "<=", ">", ">="] do
    case {column(a, j, s), column(b, j, s)} do
      {{ci, col}, nil} -> fact(op, ci, col, b, true, j, s)
      {nil, {ci, col}} -> fact(flip(op), ci, col, a, false, j, s)
      _ -> []
    end
  end

  defp facts({:between, e, lo, hi, false}, j, s) do
    case column(e, j, s) do
      nil -> []
      {ci, col} -> fact(">=", ci, col, lo, true, j, s) ++ fact("<=", ci, col, hi, true, j, s)
    end
  end

  defp facts({:in, e, {:list, items}, false}, j, s) when items != [] do
    with {ci, col} <- column(e, j, s),
         probes = Enum.map(items, &probe(col, &1, true, j, s)),
         false <- Enum.member?(probes, nil),
         [coll] <- probes |> Enum.map(&elem(&1, 1)) |> Enum.uniq() do
      [{:in, ci, Enum.map(probes, &elem(&1, 0)), coll}]
    else
      _ -> []
    end
  end

  defp facts(_, _, _), do: []

  defp flip("<"), do: ">"
  defp flip("<="), do: ">="
  defp flip(">"), do: "<"
  defp flip(">="), do: "<="
  defp flip(op), do: op

  defp fact(op, ci, col, other, col_left, j, s) do
    case probe(col, other, col_left, j, s) do
      nil ->
        []

      {{f, conv}, coll} ->
        case op do
          "=" -> [{:eq, ci, {f, conv}, coll}]
          ">" -> [{:lo, ci, {f, conv, false}, coll}]
          ">=" -> [{:lo, ci, {f, conv, true}, coll}]
          "<" -> [{:hi, ci, {f, conv, false}, coll}]
          "<=" -> [{:hi, ci, {f, conv, true}, coll}]
        end
    end
  end

  # the other side as a probe, when it reads only earlier sources and leaves the column's values as stored
  defp probe(col, other, col_left, j, s) do
    {{f, aff, coll}, refs} = Compile.with_refs(other, s)
    col_coll = {:col, col.coll || :binary}

    {pc, po} =
      if col_left,
        do: Ops.cmp_affinity(col.aff, aff),
        else: Ops.cmp_affinity(aff, col.aff) |> then(fn {a, b} -> {b, a} end)

    cmp =
      if col_left, do: Compile.cmp_coll(col_coll, coll), else: Compile.cmp_coll(coll, col_coll)

    if pc == nil and Enum.all?(refs, &(&1 < j)), do: {{f, po}, cmp}
  end

  defp column({:ref, j, ci}, j, s), do: {ci, ref_col(s, j, ci)}

  defp column({:col, t, name}, j, s) do
    case Compile.resolve(
           %{s | aliases: %{}, outer: nil},
           t && String.downcase(t),
           String.downcase(name),
           0
         ) do
      {:ok, 0, ^j, ci, col} -> {ci, col}
      _ -> nil
    end
  catch
    {:sql_error, _} -> nil
  end

  defp column(_, _, _), do: nil

  defp ref_col(_s, _j, :rowid), do: %{aff: :integer, coll: nil}
  defp ref_col(s, j, ci), do: Enum.at(Enum.at(s.sources, j).cols, ci)
end

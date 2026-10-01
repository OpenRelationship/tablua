defmodule Moss.Sql.Aggregate do
  @moduledoc """
  GROUP BY and the aggregates, as SQLite computes them: count, sum (an
  integer until a real appears, an error on integer overflow, reals summed
  by Kahan-Babuska-Neumaier as SQLite 3.43+ does), total, avg, min, max and
  group_concat, each with DISTINCT. Groups come out in the order of their
  keys. A GROUP BY term reads the group's first row; any other bare column
  its last row, or, with exactly one min() or max(), the row that gave it.
  """
  alias Moss.Sql.{Compile, Ops, Value}

  @doc "The groups of `rows` as environments whose `aggs` hold each aggregate's value."
  def groups(rows, group, aggs, outer, null_rows) do
    track = minmax(aggs)
    gfs = Enum.map(group, fn {f, _, c} -> {f, Compile.coll_of(c)} end)

    folded =
      Enum.reduce(rows, %{}, fn r, acc ->
        env = %{rows: r, outer: outer, aggs: nil}
        key = Enum.map(gfs, fn {f, c} -> Value.key(f.(env), c) end)

        {rep, states, first} =
          Map.get_lazy(acc, key, fn ->
            {r, Enum.map(aggs, &init/1), Enum.map(gfs, fn {f, _} -> f.(env) end)}
          end)

        stepped = Enum.zip_with(aggs, states, &step(&1, &2, env))
        rep = if track == nil or better?(track, states, stepped), do: r, else: rep
        Map.put(acc, key, {rep, stepped, first})
      end)

    folded =
      if group == [] and map_size(folded) == 0,
        do: %{[] => {null_rows, Enum.map(aggs, &init/1), []}},
        else: folded

    folded
    |> Enum.sort_by(&elem(&1, 0))
    |> Enum.map(fn {_, {rep, states, first}} ->
      aggs = aggs |> Enum.zip_with(states, &final/2) |> List.to_tuple()
      %{rows: rep, outer: outer, aggs: aggs, gvals: List.to_tuple(first)}
    end)
  end

  defp minmax(aggs) do
    case Enum.filter(Enum.with_index(aggs), fn {a, _} -> a.name in ["min", "max"] end) do
      [{_, i}] -> i
      _ -> nil
    end
  end

  defp better?(i, before, now), do: Enum.at(before, i).v != Enum.at(now, i).v

  defp init(a), do: %{n: 0, v: nil, seen: if(a.distinct, do: MapSet.new()), sum: nil, acc: []}

  defp step(a, st, env) do
    args = Enum.map(a.args, & &1.(env))

    case {a.name, args} do
      {"count", []} ->
        %{st | n: st.n + 1}

      {_, [nil | _]} ->
        st

      {_, [v | _]} ->
        if a.distinct do
          k = Value.key(v, a.coll)

          if MapSet.member?(st.seen, k),
            do: st,
            else: add(a, %{st | seen: MapSet.put(st.seen, k)}, args)
        else
          add(a, st, args)
        end
    end
  end

  defp add(%{name: "count"}, st, _), do: %{st | n: st.n + 1}

  defp add(%{name: n}, st, [v | _]) when n in ["sum", "total", "avg"],
    do: %{st | n: st.n + 1, sum: sum(st.sum, v)}

  defp add(%{name: "min"} = a, st, [v | _]) do
    if st.v == nil or Value.compare(v, st.v, a.coll) == :lt,
      do: %{st | v: v, n: st.n + 1},
      else: st
  end

  defp add(%{name: "max"} = a, st, [v | _]) do
    if st.v == nil or Value.compare(v, st.v, a.coll) == :gt,
      do: %{st | v: v, n: st.n + 1},
      else: st
  end

  defp add(%{name: "group_concat"}, st, [v | rest]) do
    sep =
      case rest do
        [] -> ","
        [s | _] -> Value.to_text(s) || ""
      end

    acc = if st.n == 0, do: [Value.to_text(v)], else: [Value.to_text(v), sep | st.acc]
    size = Enum.reduce(acc, 0, &(byte_size(&1) + &2))
    if size > 16 * 1024 * 1024, do: Ops.fail("string or blob too big")
    %{st | n: st.n + 1, acc: acc}
  end

  defp final(%{name: "count"}, st), do: st.n
  defp final(%{name: n}, st) when n in ["min", "max"], do: st.v
  defp final(%{name: "group_concat"}, %{n: 0}), do: nil
  defp final(%{name: "group_concat"}, st), do: st.acc |> Enum.reverse() |> IO.iodata_to_binary()
  defp final(%{name: "sum"}, %{n: 0}), do: nil
  defp final(%{name: "sum"}, st), do: sum_result(st.sum)
  defp final(%{name: "total"}, %{n: 0}), do: 0.0
  defp final(%{name: "total"}, st), do: real(st.sum)
  defp final(%{name: "avg"}, %{n: 0}), do: nil
  defp final(%{name: "avg"}, st), do: real(st.sum) / st.n

  # -- SQLite's sum ------------------------------------------------------------------------------

  defp sum(nil, v), do: sum(%{approx: false, i: 0, r: 0.0, e: 0.0, ovfl: false}, v)

  defp sum(s, v) do
    case if(is_binary(v), do: Value.apply_affinity(v, :numeric), else: v) do
      i when is_integer(i) ->
        x = s.i + i

        cond do
          s.approx ->
            step_int(s, i)

          x > Value.max_int() or x < Value.min_int() ->
            s |> kbn_init(s.i) |> Map.put(:ovfl, true) |> step_int(i)

          true ->
            %{s | i: x}
        end

      other ->
        r = Value.to_real(other)
        s = if s.approx, do: %{s | ovfl: false}, else: kbn_init(s, s.i)
        kbn(s, r)
    end
  end

  defp kbn_init(s, i) do
    s = %{s | approx: true}

    if i <= -4_503_599_627_370_496 or i >= 4_503_599_627_370_496 do
      sm = rem(i, 16384)
      %{s | r: (i - sm) * 1.0, e: sm * 1.0}
    else
      %{s | r: i * 1.0, e: 0.0}
    end
  end

  defp step_int(s, i) do
    if i <= -4_503_599_627_370_496 or i >= 4_503_599_627_370_496 do
      sm = rem(i, 16384)
      s |> kbn((i - sm) * 1.0) |> kbn(sm * 1.0)
    else
      kbn(s, i * 1.0)
    end
  end

  defp kbn(s, r) do
    t = s.r + r
    e = if abs(s.r) > abs(r), do: s.e + (s.r - t + r), else: s.e + (r - t + s.r)
    %{s | r: t, e: e}
  end

  defp sum_result(%{approx: false, i: i}), do: i
  defp sum_result(%{ovfl: true}), do: Ops.fail("integer overflow")
  defp sum_result(s), do: s.r + s.e

  defp real(%{approx: false, i: i}), do: i * 1.0
  defp real(s), do: s.r + s.e
end

defmodule Moss.Sql.Calls do
  @moduledoc """
  A function call in an expression: an aggregate (registered with the select
  being compiled, its value read from `env.aggs`), or a scalar function of
  `Moss.Sql.Functions`, with SQLite's argument checks and its rules for which
  collation min(), max() and nullif() compare under.
  """
  alias Moss.Sql.{Compile, Functions}

  @aggs ~w(count sum total avg min max group_concat)

  def compile(name, args, distinct, s) do
    if name in @aggs and (name not in ["min", "max"] or (is_list(args) and length(args) == 1)),
      do: aggregate(name, args, distinct, s),
      else: scalar(name, args, distinct, s)
  end

  defp scalar(name, args, distinct, s) do
    if distinct, do: Compile.fail("DISTINCT is only for aggregates: #{name}()")
    if args == :star, do: Compile.fail("wrong number of arguments to function #{name}()")

    case name do
      "changes" -> const(s.ctx.changes, args, name)
      "last_insert_rowid" -> const(s.ctx.last_rowid, args, name)
      "total_changes" -> const(s.ctx.total_changes, args, name)
      _ -> Functions.check!(name, length(args))
    end
    |> case do
      {_, _, _} = c ->
        c

      :ok ->
        cs = Enum.map(args, &Compile.expr(&1, s))
        fs = Enum.map(cs, &elem(&1, 0))
        now = s.ctx.now
        coll = Compile.explicit(Enum.map(cs, &elem(&1, 2)))

        # min(), max() and nullif() compare under the first argument's collation that has one
        if name in ["min", "max", "nullif"] do
          by = cs |> Enum.find_value(fn {_, _, c} -> c end) |> Compile.coll_of()
          {fn env -> Functions.compare_call(name, Enum.map(fs, & &1.(env)), by) end, nil, coll}
        else
          {fn env -> Functions.call(name, Enum.map(fs, & &1.(env)), now) end, nil, coll}
        end
    end
  end

  defp const(v, [], _), do: {fn _ -> v end, nil, nil}
  defp const(_, _, name), do: Compile.fail("wrong number of arguments to function #{name}()")

  defp aggregate(name, args, distinct, s) do
    case s.agg do
      {:collect, slot} ->
        if args != :star and name in ["count"] and length(args) > 1,
          do: Compile.fail("wrong number of arguments to function #{name}()")

        if name == "group_concat" and (args == :star or length(args) not in [1, 2]),
          do: Compile.fail("wrong number of arguments to function #{name}()")

        if args == :star and name != "count",
          do: Compile.fail("wrong number of arguments to function #{name}()")

        inner = s |> Map.put(:agg, :inside) |> Map.put(:groups, [])
        cs = if args == :star, do: [], else: Enum.map(args, &Compile.expr(&1, inner))
        aggs = Process.get(slot, [])
        i = length(aggs)

        coll =
          case cs do
            [{_, _, c} | _] -> c
            _ -> nil
          end

        Process.put(
          slot,
          aggs ++
            [
              %{
                name: name,
                args: Enum.map(cs, &elem(&1, 0)),
                distinct: distinct,
                coll: Compile.coll_of(coll)
              }
            ]
        )

        aff = if name in ["min", "max"], do: elem(hd(cs), 1), else: nil
        {fn env -> elem(env.aggs, i) end, aff, Compile.explicit(Enum.map(cs, &elem(&1, 2)))}

      :inside ->
        Compile.fail("misuse of aggregate function #{name}()")

      _ ->
        Compile.fail("misuse of aggregate: #{name}()")
    end
  end
end

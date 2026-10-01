defmodule Moss.Sql.Names do
  @moduledoc """
  Names in an expression, resolved as SQLite resolves them: a column of the
  FROM sources (ambiguous when two have it), then the result's aliases, then
  an outer query's sources (a correlated subquery). It also notes which
  sources an expression reads, for the planner (`with_refs/2`), and which
  subqueries read an outer query, so the others run once.
  """
  alias Moss.Sql.Compile

  @doc "A column's reader, affinity and collation, or an alias's expression; `no such column` otherwise."
  def column(t, name, s) do
    case resolve(s, t && String.downcase(t), String.downcase(name), 0) do
      {:ok, depth, si, ci, col} ->
        track(s, depth, si)
        {reader(depth, si, ci), col.aff, {:col, col.coll || :binary}}

      {:alias, ast} ->
        Compile.expr(ast, %{s | aliases: %{}})

      :none ->
        cond do
          t == nil and String.downcase(name) == "true" -> {fn _ -> 1 end, nil, nil}
          t == nil and String.downcase(name) == "false" -> {fn _ -> 0 end, nil, nil}
          t -> Compile.fail("no such column: #{t}.#{name}")
          true -> Compile.fail("no such column: #{name}")
        end
    end
  end

  def reader(0, si, :rowid), do: fn env -> elem(elem(env.rows, si), 0) end
  def reader(0, si, ci), do: fn env -> elem(elem(elem(env.rows, si), 1), ci) end

  def reader(d, si, ci),
    do:
      (
        f = reader(d - 1, si, ci)
        fn env -> f.(env.outer) end
      )

  @doc "Finds a column: `{:ok, depth, source, column, meta}`, `{:alias, ast}` or `:none`."
  def resolve(nil, _t, _name, _d), do: :none

  def resolve(s, t, name, d) do
    hits =
      s.sources
      |> Enum.with_index()
      |> Enum.filter(fn {src, _} -> t == nil or src.key == t end)
      |> Enum.flat_map(fn {src, si} ->
        case find_col(src, name, t != nil) do
          nil -> []
          {ci, col} -> [{si, ci, col}]
        end
      end)

    case hits do
      [{si, ci, col}] ->
        {:ok, d, si, ci, col}

      [_ | _] ->
        Compile.fail("ambiguous column name: #{if t, do: t <> ".", else: ""}#{name}")

      [] ->
        alias_ast = (t == nil and d == 0) && Map.get(s.aliases, name)

        cond do
          alias_ast -> {:alias, alias_ast}
          t != nil and not Enum.any?(s.sources, &(&1.key == t)) and s.outer == nil -> :none
          true -> resolve(s.outer, t, name, d + 1)
        end
    end
  end

  defp find_col(src, name, qualified) do
    case Enum.find_index(src.cols, &(&1.key == name)) do
      nil ->
        if src.rowid and name in ["rowid", "oid", "_rowid_"],
          do: {:rowid, %{aff: :integer, coll: nil}},
          else: nil

      i ->
        if not qualified and name in src.hidden, do: nil, else: {i, Enum.at(src.cols, i)}
    end
  end

  # which sources an expression reads (for the planner), and the subqueries that read an outer query
  def track(s, 0, si),
    do: Process.put(:sql_refs, MapSet.put(Process.get(:sql_refs, MapSet.new()), {s.id, si}))

  def track(s, d, _si) do
    corr = Process.get(:sql_corr, MapSet.new())
    Process.put(:sql_corr, mark(s, d, corr))
  end

  defp mark(_s, 0, corr), do: corr
  defp mark(s, d, corr), do: mark(s.outer, d - 1, MapSet.put(corr, s.id))

  @doc "Compiles `ast` and also gives the sources of `scope` it reads: `{compiled, MapSet of source indexes}`."
  def with_refs(ast, s) do
    saved = Process.get(:sql_refs, MapSet.new())
    Process.put(:sql_refs, MapSet.new())
    c = Compile.expr(ast, s)
    refs = for {id, si} <- Process.get(:sql_refs), id == s.id, into: MapSet.new(), do: si
    Process.put(:sql_refs, MapSet.union(saved, Process.get(:sql_refs)))
    {c, refs}
  end
end

defmodule Moss.Sql.Sort do
  @moduledoc """
  ORDER BY's sort: rows as `{values, sort_values}`, terms as `{_, :asc |
  :desc, nulls, collation}`. NULLs come first ascending and last descending
  unless NULLS FIRST/LAST says otherwise, as in SQLite; the sort is stable,
  so ties keep the order the rows came in.
  """
  alias Moss.Sql.{Budget, Value}

  def sort(rows, []), do: rows

  def sort(rows, terms) do
    n = length(rows)
    if n > 1, do: Budget.spend(n * max(1, ceil(:math.log2(n))))

    terms =
      Enum.map(terms, fn {_, dir, nulls, coll} ->
        {dir, nulls || if(dir == :asc, do: :first, else: :last), coll}
      end)

    Enum.sort(rows, fn {_, a}, {_, b} -> le(a, b, terms) end)
  end

  # a <= b, term by term; a NULL's place is its own, whatever the direction
  defp le([], [], []), do: true
  defp le([nil | xs], [nil | ys], [_ | ts]), do: le(xs, ys, ts)
  defp le([nil | _], [_ | _], [{_, nulls, _} | _]), do: nulls == :first
  defp le([_ | _], [nil | _], [{_, nulls, _} | _]), do: nulls == :last

  defp le([x | xs], [y | ys], [{dir, _, coll} | ts]) do
    case Value.compare(x, y, coll) do
      :eq -> le(xs, ys, ts)
      :lt -> dir == :asc
      :gt -> dir == :desc
    end
  end
end

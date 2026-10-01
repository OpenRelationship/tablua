defmodule Moss.Sql.Budget do
  @moduledoc """
  A statement's work, counted against the run's instruction budget: each row
  a statement visits, sorts or writes costs `#{8}` of the Lua VM's
  instructions, so a cross join of big tables ends with an error, as a Lua
  loop past the budget does, and never hangs the computer.
  """

  @per_row 8

  @doc "Starts counting with `left` instructions (`:infinity` for no limit)."
  def start(left), do: Process.put(:sql_budget, {left, 0})

  @doc "The instructions spent since `start/1`."
  def spent do
    {_, n} = Process.get(:sql_budget, {:infinity, 0})
    n
  end

  def spend(rows) do
    case Process.get(:sql_budget) do
      {:infinity, n} ->
        Process.put(:sql_budget, {:infinity, n + rows * @per_row})

      {left, n} ->
        n = n + rows * @per_row

        if n > left,
          do:
            throw(
              {:sql_error, "interrupted: the statement ran past the run's instruction budget"}
            )

        Process.put(:sql_budget, {left, n})

      nil ->
        :ok
    end
  end
end

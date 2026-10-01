defmodule Moss.SqlDiff do
  @moduledoc """
  The differential check of the agent's SQL: the same statements run on
  `Moss.Sql.Engine` and on real SQLite (exqlite, in memory), their answers
  compared. A query's rows compare in order when it has ORDER BY and as a
  sorted list when it does not; an error compares by its message.
  """
  alias Exqlite.Sqlite3
  alias Moss.Sql.Engine

  def new do
    {:ok, conn} = Sqlite3.open(":memory:")
    %{conn: conn, db: Engine.new()}
  end

  def close(%{conn: conn}), do: Sqlite3.close(conn)

  @doc "Runs one statement on both; `{state, :same | {:differ, ours, theirs}}`."
  def run(st, sql, params \\ []) do
    theirs = real(st.conn, sql, params)

    {db, ours} =
      case Engine.exec(st.db, sql, params, fn _ -> :ok end) do
        {:ok, db, r} -> {db, {:ok, r.names, Enum.map(r.rows, &plain/1)}}
        {:error, db, why} -> {db, {:error, why}}
      end

    ordered = Regex.match?(~r/order\s+by/i, sql)
    verdict = if same?(ours, theirs, ordered), do: :same, else: {:differ, ours, theirs}
    {%{st | db: db}, verdict}
  end

  @doc "Only the rows that differ, for reading a failure: `{sql, only ours, only theirs}`."
  def brief({sql, {:ok, n, a}, {:ok, n, b}, prev}), do: {sql, n, a -- b, b -- a, after: prev}
  def brief(d), do: d

  @doc "Runs a list of statements on fresh databases; the ones that differ, as `{sql, ours, theirs, previous sql}`."
  def differences(statements, params \\ []) do
    st = new()

    {st, diffs, _} =
      Enum.reduce(statements, {st, [], nil}, fn sql, {st, acc, prev} ->
        case run(st, sql, params) do
          {st, :same} -> {st, acc, sql}
          {st, {:differ, ours, theirs}} -> {st, [{sql, ours, theirs, prev} | acc], sql}
        end
      end)

    close(st)
    Enum.reverse(diffs)
  end

  defp plain(row),
    do:
      Enum.map(row, fn
        {:blob, b} -> b
        v -> v
      end)

  defp same?({:ok, n1, r1}, {:ok, n2, r2}, true), do: n1 == n2 and eq_rows(r1, r2)

  defp same?({:ok, n1, r1}, {:ok, n2, r2}, false),
    do: n1 == n2 and eq_rows(Enum.sort(r1), Enum.sort(r2))

  defp same?({:error, a}, {:error, b}, _), do: a == b
  defp same?(_, _, _), do: false

  # values equal as SQLite returns them: an integer is not a real
  defp eq_rows(a, b) when length(a) != length(b), do: false

  defp eq_rows(a, b) do
    Enum.zip(a, b)
    |> Enum.all?(fn {x, y} ->
      length(x) == length(y) and Enum.all?(Enum.zip(x, y), fn {v, w} -> v === w end)
    end)
  end

  @doc "A statement on real SQLite: `{:ok, names, rows}` or `{:error, message}`."
  def real(conn, sql, params) do
    case Sqlite3.prepare(conn, sql) do
      {:ok, stmt} ->
        try do
          with :ok <- Sqlite3.bind(stmt, params),
               {:ok, cols} <- Sqlite3.columns(conn, stmt),
               {:ok, rows} <- Sqlite3.fetch_all(conn, stmt) do
            {:ok, cols, rows}
          else
            {:error, why} -> {:error, to_string(why)}
          end
        after
          Sqlite3.release(conn, stmt)
        end

      {:error, why} ->
        {:error, to_string(why)}
    end
  end
end

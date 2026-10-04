defmodule Moss.Computer.Tablua do
  @moduledoc """
  The agent harness's own tables in its computer's file (Arock's library/tablua, issue #1): the harness's Lua writes
  and reads them through `__host.agent_sql`, and this is that port's door. Only statements over tables named
  `tablua_` pass, each statement checked (a view too, over tablua_ tables alone, as tablua_break is): the log's events, the computer's disk and its apps' data stay out of reach.
  Attaching a second file is allowed only for the node's shared experience (`Moss.Computer.Experience.path/0`).
  The harness is host code in a state no agent script gets; this keeps a mistake in it from touching anything else.
  """
  alias Moss.Db

  @verbs ~r/\A(create table if not exists|create view if not exists|insert or replace into|insert into|select|update|delete from|attach database)\b/i
  # a word that names a table, after the clauses that name one
  @named ~r/\b(?:from|into|update|join|(?:table|view)(?:\s+if\s+not\s+exists)?)\s+([A-Za-z_][\w.]*)/i

  @doc "Runs `sql` with `params` on the computer's file when every statement only names tablua_ tables."
  def exec(conn, sql, params) do
    case allowed(sql, params) do
      :ok -> Db.exec(conn, sql, params)
      {:error, why} -> {:error, why}
    end
  end

  @doc ":ok, or {:error, why} naming the statement refused."
  def allowed(sql, params) do
    sql
    |> String.split(";")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.find_value(:ok, fn s ->
      case check(s, params) do
        :ok -> nil
        why -> {:error, "tablua: refused (#{why}): " <> String.slice(s, 0, 80)}
      end
    end)
  end

  defp check(s, params) do
    cond do
      not Regex.match?(@verbs, s) -> "not a statement the harness makes"
      Regex.match?(~r/\Aattach/i, s) -> attach(params)
      true -> tables(s)
    end
  end

  defp attach([path | _]) do
    if is_binary(path) and path == Moss.Computer.Experience.path(), do: :ok, else: "attach only the shared experience"
  end

  defp attach(_), do: "attach only the shared experience"

  defp tables(s) do
    names = for [_, name] <- Regex.scan(@named, s), do: name |> String.split(".") |> List.last()

    cond do
      names == [] -> "names no table"
      Enum.all?(names, &String.starts_with?(&1, "tablua_")) -> :ok
      true -> "names a table that is not tablua_"
    end
  end
end

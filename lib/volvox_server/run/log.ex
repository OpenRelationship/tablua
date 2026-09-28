defmodule VolvoxServer.Run.Log do
  @moduledoc """
  Reads of a run's file for the host itself (broadcasts and the run page),
  straight from the store's tables: the log (`events`, `args`), which is
  append-only, and the folded `tasks`. Writes go only through the core.
  """
  alias VolvoxServer.Db

  @doc "Events after `seq` in log order: `%{seq, task, keyword, actor, args}`."
  def after_seq(conn, seq) do
    {:ok, rows} =
      Db.exec(
        conn,
        "select e.seq, e.task, e.keyword, e.actor, a.value from events e" <>
          " left join args a on a.seq = e.seq where e.seq > ? order by e.seq, a.pos",
        [seq]
      )

    rows
    |> Enum.chunk_by(& &1["seq"])
    |> Enum.map(fn [first | _] = group ->
      %{
        seq: first["seq"],
        task: first["task"],
        keyword: first["keyword"],
        actor: first["actor"],
        args: for(r <- group, Map.has_key?(r, "value"), do: r["value"])
      }
    end)
  end

  def last_seq(conn) do
    {:ok, [row]} = Db.exec(conn, "select coalesce(max(seq), 0) as seq from events", [])
    row["seq"]
  end

  @doc "Every task with its machine, current state and last test result."
  def tasks(conn) do
    {:ok, rows} =
      Db.exec(conn, "select task, machine, state, result, detail from tasks order by task", [])

    Enum.map(rows, fn r ->
      %{
        task: r["task"],
        machine: r["machine"],
        state: r["state"],
        result: r["result"],
        detail: r["detail"]
      }
    end)
  end
end

defmodule Moss.Computer.Session do
  @moduledoc """
  A computer's own state beside its files (the terminal's lines, the browser's tabs, its folder and environment),
  in its disk's `kept` table, kept after every command and read back when it wakes.

  Another connection can hold the file past SQLite's own wait (`busy_timeout`, 5 s): Litestream checkpointing it
  on a loaded node. So a busy file is tried again, `tries` times (5) with a growing pause, and one still busy is
  `{:error, why}`, never a crash of the computer: the next command keeps it.
  """
  alias Moss.Db

  def keep(disk, term, opts \\ []) do
    sql = "insert or replace into kept (key, value) values ('session', ?1)"

    case retried(fn -> Db.exec(disk.conn, sql, [{:blob, :erlang.term_to_binary(term)}]) end, opts) do
      {:ok, _} -> :ok
      e -> e
    end
  end

  def kept(disk, default) do
    case retried(
           fn -> Db.exec(disk.conn, "select value from kept where key = 'session'", []) end,
           []
         ) do
      {:ok, [%{"value" => v}]} -> :erlang.binary_to_term(v, [:safe])
      _ -> default
    end
  end

  # a busy file again after 50, 100, 150 ms...; any other answer at once
  defp retried(f, opts, n \\ 1) do
    case f.() do
      {:error, why} = e ->
        if n < Keyword.get(opts, :tries, 5) and why =~ ~r/busy|locked/i do
          Process.sleep(50 * n)
          retried(f, opts, n + 1)
        else
          e
        end

      result ->
        result
    end
  end
end

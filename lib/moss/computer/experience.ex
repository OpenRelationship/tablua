defmodule Moss.Computer.Experience do
  @moduledoc """
  Experience shared between computers (Arock's continual learning, 2026-10-04): the rows agent.memory learns each
  step from (Request, Step, Sure, and a step's or request's Outcome), kept in one file for every computer on the
  node, so a computer's agent learns from every other's steps and not only its own. A fresh computer otherwise
  starts with nothing to learn from, and what one learned died with it.

  The file is MOSS_EXPERIENCE, or `config :moss, :experience`; with neither, a computer learns from its own log
  alone. Another computer's tasks are read as `<computer>:<task>`, so they never join its own.
  """
  alias Moss.Db

  @keywords ~w(Request Step Sure Outcome)

  # memory is folded again at every step of a run, so it reads the newest rows only
  @newest 4000

  @doc "The shared file, or nil."
  def path, do: System.get_env("MOSS_EXPERIENCE") || Application.get_env(:moss, :experience)

  @doc "Every other computer's rows, oldest first, as `Moss.Log.rows/2` gives them; [] with no shared file."
  def rows(id) do
    with p when is_binary(p) <- path(),
         {:ok, conn} <- open(p) do
      try do
        {:ok, rows} =
          Db.exec(
            conn,
            "select computer, task, keyword, args from (select * from experience where computer <> ? " <>
              "order by seq desc limit ?) order by seq",
            [id, @newest]
          )

        for r <- rows,
            do: %{
              "task" => r["computer"] <> ":" <> r["task"],
              "keyword" => r["keyword"],
              "args" => Jason.decode!(r["args"])
            }
      after
        Exqlite.Sqlite3.close(conn)
      end
    else
      _ -> []
    end
  end

  @doc "A row this computer's agent wrote, shared when it is one memory learns from; :ok either way."
  def add(id, task, keyword, args) do
    with true <- shared?(keyword, args),
         p when is_binary(p) <- path(),
         {:ok, conn} <- open(p) do
      try do
        {:ok, _} =
          Db.exec(conn, "insert into experience (computer, task, keyword, args) values (?, ?, ?, ?)", [
            id,
            task,
            keyword,
            Jason.encode!(Enum.map(args, &to_string/1))
          ])
      after
        Exqlite.Sqlite3.close(conn)
      end
    end

    :ok
  end

  defp shared?("Outcome", [kind | _]), do: kind in ["step", "request"]
  defp shared?(keyword, _args), do: keyword in @keywords

  defp open(p) do
    with {:ok, conn} <- Db.open(p),
         {:ok, _} <-
           Db.exec(
             conn,
             "create table if not exists experience (seq integer primary key, computer text not null, " <>
               "task text not null, keyword text not null, args text not null)",
             []
           ) do
      {:ok, conn}
    end
  end
end

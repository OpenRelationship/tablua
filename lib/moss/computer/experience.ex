defmodule Moss.Computer.Experience do
  @moduledoc """
  Experience shared between computers (Arock's continual learning, 2026-10-04): every computer's finished runs as
  Tablua rows (core/tablua), in one file for the node, so a computer's agent learns which move helps from every
  other's steps and not only its own. A fresh computer otherwise starts with nothing to learn from, and what one
  learned died with it.

  The file is MOSS_EXPERIENCE, or `config :moss, :experience`; with neither, a computer learns from its own rows
  alone. Another computer's tasks are kept as `<computer>|<task>`, so they never join its own.
  """
  alias Moss.Db

  @doc "The shared file, or nil."
  def path, do: System.get_env("MOSS_EXPERIENCE") || Application.get_env(:moss, :experience)

  # what TabPFN learns from (core/tablua's training query): each decided step, its numbers, how it turned out, its
  # labels and effects, and how its run ended
  @tablua ~w(tablua_state tablua_candidate tablua_decision tablua_outcome tablua_feature tablua_label tablua_effect tablua_run)

  @doc """
  A finished run's Tablua rows (conn, the computer's own file) into the shared file, each task as
  `<computer>|<task>` so no computer's joins another's; :ok, with no shared file too. The shared tables are made as
  the computer's are, from its own schema. A computer's harness reads them attached (core/tablua's t:attach).
  """
  def share(id, conn) do
    with p when is_binary(p) <- path(),
         {:ok, shared} <- Db.open(p) do
      try do
        {:ok, made} = Db.exec(conn, "select name, sql from sqlite_master where type = 'table'", [])
        for %{"name" => name, "sql" => sql} <- made, name in @tablua do
          Db.exec(shared, String.replace(sql, ~r/\ACREATE TABLE /i, "CREATE TABLE IF NOT EXISTS "), [])
        end
      after
        Exqlite.Sqlite3.close(shared)
      end

      {:ok, _} = Db.exec(conn, "attach database ? as experience_share", [p])

      try do
        for name <- @tablua, cols = columns(conn, name), cols != [] do
          select = Enum.map_join(cols, ", ", &if(&1 == "task", do: "? || '|' || task", else: &1))
          Db.exec(conn, "insert or replace into experience_share.#{name} (#{Enum.join(cols, ", ")}) " <>
            "select #{select} from main.#{name}", [id])
        end
      after
        Db.exec(conn, "detach database experience_share", [])
      end
    end

    :ok
  end

  defp columns(conn, name) do
    case Db.exec(conn, "select name from pragma_table_info(?)", [name]) do
      {:ok, rows} -> for %{"name" => c} <- rows, do: c
      _ -> []
    end
  end
end

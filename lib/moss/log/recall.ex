defmodule Moss.Log.Recall do
  @moduledoc """
  What `Moss.Log.append/6` writes to arock-log's recall index (`recall.lua`), from
  Elixir, every agent byte a bound value: SQLite stores and compares the
  tokens and never reads the text they came from (Arock's PROJECT.md §14.7,
  item 9).

  An event is document kind 0, its doc its seq; a text blob is kind 1, its doc
  its `recall_blobs` id. Their postings go to `recall_pending` (kind, doc,
  term, tf, len); arock-log's `FLUSH_SQL` packs them into `recall_blocks` once
  `FLUSH` rows wait. A text file's path is a `recall_paths` row.
  """
  alias Moss.Db
  alias Moss.Log.Tokens

  # (term, tf) rows a statement: two values each, well under SQLite's 32,766
  @rows 4_000

  @doc "arock-log's recall constants, read once from `recall.lua`: K1, B, QUERY_TERMS, FLUSH and FLUSH_SQL."
  def alog do
    case :persistent_term.get({__MODULE__, :alog}, nil) do
      nil ->
        code =
          "local r = require('arock-log.recall') return r.K1, r.B, r.QUERY_TERMS, r.FLUSH, r.FLUSH_SQL"

        {[k1, b, terms, flush, sql], _} = Lua.eval!(Moss.Lua.base(), code)
        v = %{k1: k1, b: b, query_terms: terms, flush: flush, flush_sql: sql}
        tap(v, &:persistent_term.put({__MODULE__, :alog}, &1))

      v ->
        v
    end
  end

  @doc "A path's tokens as `recall_paths` keeps them: {len, terms joined by a space}."
  def path(p) do
    list = Tokens.tokens(p)
    {length(list), Enum.join(list, " ")}
  end

  @doc """
  The bounds of what lies under `p` as a folder, `p/` up to `p0` ('0' is the
  byte after '/'): fold.lua's UNDER with its concatenation done here, so a
  statement only compares bound bytes.
  """
  def under(p), do: {p <> "/", p <> "0"}

  @doc """
  A document's postings, `[{term, tf}]`: an event's (`:event`, its doc the
  newest seq) or a blob's (`{:blob, id}`, its doc the `recall_blobs` id of the
  log's blob `id`).
  """
  def pend(conn, :event, rows, len),
    do: pend(conn, "0, (select max(seq) from events)", [], rows, len)

  def pend(conn, {:blob, id}, rows, len),
    do: pend(conn, "1, (select id from recall_blobs where blob = ?)", [id], rows, len)

  defp pend(_conn, _doc, _params, [], _len), do: :ok

  defp pend(conn, doc, params, rows, len) do
    rows
    |> Enum.chunk_every(@rows)
    |> Enum.reduce_while(:ok, fn chunk, :ok ->
      sql =
        "insert into recall_pending (kind, doc, term, tf, len) select " <>
          doc <>
          ", column1, column2, ? from (values " <>
          Enum.map_join(chunk, ", ", fn _ -> "(?, ?)" end) <> ")"

      values = Enum.flat_map(chunk, fn {t, n} -> [t, n] end)

      case Db.exec(conn, sql, params ++ [len | values]) do
        {:ok, _} -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  @doc "Packs the pending postings into blocks once `pending` reaches arock-log's FLUSH."
  def settle(conn, pending) do
    %{flush: flush, flush_sql: sql} = alog()

    if pending >= flush,
      do: with({:ok, _} <- Db.exec(conn, sql, []), do: :ok),
      else: :ok
  end

  @doc """
  A Move File's folds past what the append trigger does (which drops a file
  at `to`): `from` and all under it take their new paths in `files`, with the
  newest seq, and in `recall_paths`, tokenized again. fold.lua's Move File and
  recall.lua's `move`, the new paths made here rather than by `substr`.
  """
  def move(conn, from, to) do
    {lo, hi} = under(from)
    range = "(path = ? or (path >= ? and path < ?))"
    moved = fn p -> to <> binary_part(p, byte_size(from), byte_size(p) - byte_size(from)) end

    with {:ok, files} <-
           Db.exec(conn, "select path from files where #{range} order by path", [from, lo, hi]),
         :ok <- each_chunk(files, &move_files(conn, &1, moved)),
         {:ok, paths} <-
           Db.exec(conn, "select path, blob from recall_paths where #{range}", [from, lo, hi]),
         {:ok, _} <- Db.exec(conn, "delete from recall_paths where #{range}", [from, lo, hi]) do
      each_chunk(paths, &insert_paths(conn, &1, moved))
    end
  end

  defp each_chunk(rows, f) do
    rows
    |> Enum.chunk_every(div(@rows, 2))
    |> Enum.reduce_while(:ok, fn chunk, :ok ->
      case f.(chunk) do
        {:ok, _} -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp move_files(conn, rows, moved) do
    Db.exec(
      conn,
      "update files set path = v.column2, seq = (select max(seq) from events) from (values " <>
        Enum.map_join(rows, ", ", fn _ -> "(?, ?)" end) <> ") as v where files.path = v.column1",
      Enum.flat_map(rows, fn %{"path" => p} -> [p, moved.(p)] end)
    )
  end

  defp insert_paths(conn, rows, moved) do
    Db.exec(
      conn,
      "insert into recall_paths (path, blob, len, terms) values " <>
        Enum.map_join(rows, ", ", fn _ -> "(?, ?, ?, ?)" end),
      Enum.flat_map(rows, fn %{"path" => p, "blob" => id} ->
        to = moved.(p)
        {len, terms} = path(to)
        [to, id, len, terms]
      end)
    )
  end
end

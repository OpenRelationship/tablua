defmodule Moss.Log.Search do
  @moduledoc """
  Recall over a computer's log, in Elixir: arock-log's `recall.lua` search (events,
  files, bm25 with its K1 and B), which takes about 100 ms at 1,000 events in
  tv-labs lua. The query is tokenized here (`Moss.Log.Tokens`), so no query
  text is syntax, and SQLite only compares the terms as bound values.

  Results are best first, ties by key, as `recall.lua` ranks them, with the
  same scores: `[{seq, score}]` for events, `[{path, score}]` for files.
  """
  alias Moss.Db
  alias Moss.Log.{Recall, Tokens}

  @event 0
  @blob 1

  @doc "Events and files holding any word of `q`: `%{events: [{seq, score}], files: [{path, score}]}`."
  def recall(conn, q, n \\ 10), do: %{events: events(conn, q, n), files: files(conn, q, n)}

  @doc "Events holding any word of `q`, best first."
  def events(conn, q, n \\ 10) do
    with [_ | _] = list <- terms(q),
         posts = postings(conn, @event, list),
         [_ | _] <- posts,
         {:ok, [stats]} <-
           Db.exec(conn, "select count(*) as n, sum(len) as total from recall_events", []) do
      hits = hits(length(list), for({i, seq, tf, _} <- posts, do: {i, seq, tf}))
      lens = Map.new(posts, fn {_, seq, _, len} -> {seq, len} end)
      rank(hits, lens, stats["n"], stats["total"], n)
    else
      _ -> []
    end
  end

  @doc "Files whose path or content holds any word of `q`, best first. It reads every text file's path row."
  def files(conn, q, n \\ 10) do
    with [_ | _] = list <- terms(q),
         {:ok, files} <-
           Db.exec(
             conn,
             "select p.path, p.blob, p.len + b.len as len, p.terms from recall_paths p " <>
               "join recall_blobs b on b.id = p.blob",
             []
           ) do
      at = list |> Enum.with_index() |> Map.new()
      by = Enum.group_by(files, & &1["blob"], & &1["path"])

      in_paths =
        for f <- files,
            w <- String.split(f["terms"] || "", " ", trim: true),
            i <- [at[w]],
            i != nil,
            do: {i, f["path"], 1}

      in_blobs =
        for {i, id, tf, _} <- postings(conn, @blob, list),
            path <- Map.get(by, id, []),
            do: {i, path, tf}

      case in_paths ++ in_blobs do
        [] ->
          []

        found ->
          lens = Map.new(files, &{&1["path"], &1["len"]})
          total = files |> Enum.map(& &1["len"]) |> Enum.sum()
          rank(hits(length(list), found), lens, length(files), total, n)
      end
    else
      _ -> []
    end
  end

  # a query's distinct tokens, in order, at most QUERY_TERMS
  defp terms(q), do: q |> Tokens.tokens() |> Enum.uniq() |> Enum.take(Recall.alog().query_terms)

  # one %{key => tf} per query term, in query order
  defp hits(count, found) do
    by =
      Enum.reduce(found, %{}, fn {i, k, tf}, acc -> Map.update(acc, {i, k}, tf, &(&1 + tf)) end)

    empty = Map.new(0..(count - 1), &{&1, %{}})

    by
    |> Enum.reduce(empty, fn {{i, k}, tf}, acc -> Map.update!(acc, i, &Map.put(&1, k, tf)) end)
    |> Enum.sort()
    |> Enum.map(&elem(&1, 1))
  end

  # The postings of one kind for the terms of list, pending and packed: {term's index, doc, tf, len}.
  defp postings(conn, kind, list) do
    at = list |> Enum.with_index() |> Map.new()
    marks = Enum.map_join(list, ", ", fn _ -> "?" end)

    {:ok, pending} =
      Db.exec(
        conn,
        "select doc, term, tf, len from recall_pending where kind = ? and term in (#{marks})",
        [kind | list]
      )

    {:ok, blocks} =
      Db.exec(
        conn,
        "select term, first, postings from recall_blocks where kind = ? and term in (#{marks})",
        [kind | list]
      )

    packed =
      for b <- blocks,
          [doc, tf, len] <- b["postings"] |> String.split(" ") |> Enum.chunk_every(3),
          do:
            {at[b["term"]], b["first"] + String.to_integer(doc), String.to_integer(tf),
             String.to_integer(len)}

    for(r <- pending, do: {at[r["term"]], r["doc"], r["tf"], r["len"]}) ++ packed
  end

  # FTS5's bm25, as recall.lua's rank: for each term, idf * f * (k1 + 1) / (f + k1 * (1 - b + b * len /
  # avgdl)) with idf = ln((N - n + 0.5) / (n + 0.5)), 1e-6 when that is not above 0; summed in term order.
  defp rank(hits, lens, n_docs, total, n) do
    %{k1: k1, b: b} = Recall.alog()
    avgdl = total / n_docs

    hits
    |> Enum.reduce(%{}, fn hit, score ->
      df = map_size(hit)
      idf = :math.log((n_docs - df + 0.5) / (df + 0.5))
      idf = if idf <= 0, do: 1.0e-6, else: idf

      Enum.reduce(hit, score, fn {key, f}, score ->
        s = idf * (f * (k1 + 1)) / (f + k1 * (1 - b + b * lens[key] / avgdl))
        Map.update(score, key, 0 + s, &(&1 + s))
      end)
    end)
    |> Enum.sort(fn {ka, sa}, {kb, sb} -> sa > sb or (sa == sb and ka <= kb) end)
    |> Enum.take(n)
  end
end

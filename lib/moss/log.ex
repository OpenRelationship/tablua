defmodule Moss.Log do
  @moduledoc """
  A computer's log (Arock's PROJECT.md §15): alog, in the computer's own
  SQLite file. Its file writes, runs, app requests and mail are events
  (`Write File`, `Run Command`, `Serve Request`, `Send Mail`, ...), and its
  disk is the files folded from them.

  alog is the single source of its tables and rules. `open/1` runs alog's own
  Lua (`arock.log` in `priv/lua/host.lua`) whenever the file's state is not at
  alog's version, so alog makes the tables and folds the log itself. `alog/3`
  calls any of alog's methods the same way (`rebuild`, `recall`, `events`).

  `append/6` is the hot path, the cost of every command and file write. It is
  an insert into the view `moss_append_2`, whose trigger writes what alog's
  `append` writes (`init.lua`'s `record`, `blobs.lua`'s content kept once by
  id, `fold.lua`'s folds for the four disk keywords), each argument its own
  bound value, then the event's recall postings (`Moss.Log.Recall`), all in one
  savepoint. Recall is tokenized here (`Moss.Log.Tokens`, held to alog's
  `tokens_vectors.lua`), so SQLite stores and compares an agent's bytes and
  never parses them (Arock's PROJECT.md §14.7 item 9); a Move File's new paths
  are made here too. A fresh tv-labs state per event costs about 0.4 ms, and
  alog's dozen statements a dozen trips through Exqlite's dirty schedulers,
  hence the trigger. The tests hold all of it to alog's own `append`,
  `rebuild` and index of the whole log, dump for dump.

  Content is kept once by its SHA-256, as alog does with a host's digest; an
  id that names other bytes (a SHA-256 collision) stops the event rather than
  reuse them.
  """
  alias Moss.Db
  alias Moss.Log.{Recall, Tokens}

  @recall 65_536
  @tokens elem(Tokens.limits(), 1)

  @doc "alog's declared keywords with their arguments, read from alog's `kinds.lua`."
  def kinds, do: cached(:kinds, fn -> read_alog("require('alog.kinds').args") end)

  defp version, do: cached(:version, fn -> read_alog("require('alog.schema').version") end)

  defp read_alog(code) do
    {[v], lua} = Lua.eval!(Moss.Lua.base(), "return " <> code)
    v = Moss.Lua.decode(lua, v)
    if is_list(v), do: Map.new(v, fn {k, args} -> {k, Moss.Lua.list(args)} end), else: v
  end

  defp cached(key, f) do
    case :persistent_term.get({__MODULE__, key}, nil) do
      nil -> tap(f.(), &:persistent_term.put({__MODULE__, key}, &1))
      v -> v
    end
  end

  # init.lua's record and fold.lua's folds, as one trigger over bound values: a1..a6 an event's arguments as
  # logged (content by its blob id), id1/c1 and id2/c2 its content arguments' ids and bytes, len its recall
  # length; lo and hi a Delete File's bounds (Recall.under/1); blen a newly indexed text blob's length, plen
  # and terms a written text file's path tokens (null when binary). The new event is the newest seq. An
  # event's postings and a Move File's new paths follow from Elixir (Moss.Log.Recall), in the same savepoint.
  @append """
  drop view if exists moss_append_1;
  create view if not exists moss_append_2
    (at, task, keyword, actor, a1, a2, a3, a4, a5, a6, id1, c1, id2, c2, len, lo, hi, blen, plen, terms) as
    select null, null, null, null, null, null, null, null, null, null,
      null, null, null, null, null, null, null, null, null, null where 0;
  create trigger if not exists moss_append_2_fold instead of insert on moss_append_2 begin
    select raise(abort, 'alog: a blob id names other bytes')
      where exists (select 1 from blobs where id = new.id1 and content is not new.c1)
         or exists (select 1 from blobs where id = new.id2 and content is not new.c2);
    insert or ignore into blobs (id, content) select new.id1, new.c1 where new.id1 is not null;
    insert or ignore into blobs (id, content) select new.id2, new.c2 where new.id2 is not null;
    insert into events (at, task, keyword, actor) values (new.at, new.task, new.keyword, new.actor);
    insert into args (seq, pos, value)
      select (select max(seq) from events), pos, value
      from (select 1 as pos, new.a1 as value union all select 2, new.a2 union all select 3, new.a3
            union all select 4, new.a4 union all select 5, new.a5 union all select 6, new.a6)
      where value is not null;
    insert into recall_events (seq, len) values ((select max(seq) from events), new.len);

    insert or replace into files (path, dir, blob, seq)
      select new.a1, 0, new.a2, (select max(seq) from events) where new.keyword = 'Write File';
    delete from recall_paths where new.keyword = 'Write File' and path = new.a1;
    insert into recall_blobs (blob, len) select new.a2, new.blen where new.keyword = 'Write File' and new.blen is not null;
    insert into recall_paths (path, blob, len, terms)
      select new.a1, (select id from recall_blobs where blob = new.a2), new.plen, new.terms
      where new.keyword = 'Write File' and new.terms is not null;

    insert or ignore into files (path, dir, blob, seq)
      select new.a1, 1, null, (select max(seq) from events) where new.keyword = 'Make Folder';

    delete from files where new.keyword = 'Delete File' and (path = new.a1 or (path >= new.lo and path < new.hi));
    delete from recall_paths
      where new.keyword = 'Delete File' and (path = new.a1 or (path >= new.lo and path < new.hi));

    delete from files where new.keyword = 'Move File' and path = new.a2 and dir = 0;
    delete from recall_paths where new.keyword = 'Move File' and path = new.a2;
  end;
  """
  @doc "Makes the log's tables, or folds its state again, through alog when the file is not at alog's version."
  def open(conn) do
    current =
      case Db.exec(conn, "select version from alog_state", []) do
        {:ok, [%{"version" => v}]} -> v == version()
        _ -> false
      end

    with :ok <- if(current, do: :ok, else: open_alog(conn)),
         {:ok, _} <- Db.exec(conn, @append, []),
         do: :ok
  end

  defp open_alog(conn) do
    case Moss.Lua.call(:log, [nil], db: conn) do
      {:ok, _} -> :ok
      {:error, why} -> {:error, why}
    end
  end

  @doc "Calls alog's `method` with `args` on this disk's log, through alog's own Lua."
  def alog(%{conn: conn}, method, args), do: alog(conn, method, args)
  def alog(conn, method, args), do: Moss.Lua.call(:log, [method | args], db: conn)

  @doc """
  Logs one event and folds it, atomically, as alog's `append`: `:ok`, or
  `{:error, why}` with nothing written (a full disk is `"database or disk is
  full"`). `at` is the event's time, now by default. Inside a transaction the
  caller holds, it is part of that one.
  """
  def append(conn, task, keyword, args, actor, at \\ nil) do
    spec = Map.get(kinds(), keyword, [])

    unless length(args) == length(spec) and Enum.all?(args, &is_binary/1),
      do: raise(ArgumentError, "#{keyword} takes #{Enum.join(spec, ", ")}: #{inspect(args)}")

    # content arguments by their blob id, the recall text of each argument
    {kept, words, blobs} =
      Enum.zip(args, spec)
      |> Enum.reduce({[], [], []}, fn {v, a}, {kept, words, blobs} ->
        if String.ends_with?(a, "*") do
          id = Base.encode16(:crypto.hash(:sha256, v), case: :lower)
          {[id | kept], [text(v) || "" | words], [{id, {:blob, v}} | blobs]}
        else
          {[v | kept], [v | words], blobs}
        end
      end)

    {kept, words, blobs} = {Enum.reverse(kept), Enum.reverse(words), Enum.reverse(blobs)}

    if Enum.all?(kept, &String.valid?/1),
      do: write(conn, at, task, keyword, actor, args, kept, words, blobs),
      else: {:error, "an argument is not UTF-8"}
  end

  defp write(conn, at, task, keyword, actor, args, kept, words, blobs) do
    [{id1, c1}, {id2, c2}] = Enum.take(blobs ++ [{nil, nil}, {nil, nil}], 2)
    file = if keyword == "Write File", do: id1

    with {:ok, [pre]} <-
           Db.exec(
             conn,
             "select (select count(*) from recall_pending) as pending, " <>
               "(select id from recall_blobs where blob = ?) as rid",
             [file]
           ),
         {:ok, _} <- Db.exec(conn, "savepoint moss_append", []) do
      # the event's tokens are its keyword's and each argument's, as if joined by spaces; a written file's
      # content (its last argument) is tokenized and counted once, for its blob and for the event
      lists = Enum.map(words, &Tokens.tokens/1)
      [a1, a2 | _] = kept ++ [nil, nil]

      {blob, row} =
        cond do
          file == nil -> {nil, [nil, nil, nil]}
          Map.has_key?(pre, "rid") -> {nil, [nil | Tuple.to_list(Recall.path(a1))]}
          text(List.last(args)) == nil -> {nil, [nil, nil, nil]}
          true -> blob_doc(List.last(lists), a1)
        end

      {erows, elen} = event_doc([Tokens.tokens(keyword) | lists], blob)

      {lo, hi} = if keyword == "Delete File", do: Recall.under(a1), else: {nil, nil}

      params =
        [at || clock(), task, keyword, actor] ++ Enum.take(kept ++ List.duplicate(nil, 6), 6)

      result =
        with :ok <- Recall.settle(conn, pre["pending"]),
             {:ok, _} <-
               Db.exec(
                 conn,
                 "insert into moss_append_2 values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
                 params ++ [id1, c1, id2, c2, elen, lo, hi] ++ row
               ),
             :ok <- Recall.pend(conn, :event, erows, elen),
             :ok <-
               if(blob,
                 do: Recall.pend(conn, {:blob, file}, elem(blob, 0), elem(blob, 1)),
                 else: :ok
               ),
             do: if(keyword == "Move File", do: Recall.move(conn, a1, a2), else: :ok)

      finish(conn, result)
    else
      {:error, why} -> {:error, to_string(why)}
    end
  end

  # a new text blob: its postings and length, and the row for the trigger (blen, plen, terms)
  defp blob_doc(list, path) do
    {rows, len} = Tokens.count(list)
    {plen, terms} = Recall.path(path)
    {{rows, len}, [len, plen, terms]}
  end

  # tokens.lua reads no further than its 10,000th token, so neither does the joined text; a new blob's counts
  # are the event's tail when the whole fits
  defp event_doc(lists, nil), do: lists |> Enum.concat() |> Enum.take(@tokens) |> Tokens.count()

  defp event_doc(lists, {rows, len}) do
    head = lists |> Enum.drop(-1) |> Enum.concat()

    if length(head) + len <= @tokens do
      tf = Enum.reduce(head, Map.new(rows), fn t, tf -> Map.update(tf, t, 1, &(&1 + 1)) end)
      {Map.to_list(tf), length(head) + len}
    else
      event_doc(lists, nil)
    end
  end

  defp finish(conn, :ok) do
    with {:ok, _} <- Db.exec(conn, "release moss_append", []), do: :ok
  end

  defp finish(conn, {:error, why}) do
    Db.exec(conn, "rollback to moss_append; release moss_append", [])
    {:error, to_string(why)}
  end

  def clock, do: DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

  # blobs.lua's text: what recall indexes, no NUL byte and at most 64 KB
  defp text(s) do
    cond do
      String.contains?(s, <<0>>) -> nil
      byte_size(s) > @recall -> binary_part(s, 0, @recall)
      true -> s
    end
  end
end

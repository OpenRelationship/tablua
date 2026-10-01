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

  `append/6` is the hot path, the cost of every command and file write, so it
  is one SQL statement: an insert into the view `moss_append_1`, whose trigger
  writes what alog's `append` writes (`init.lua`'s `record`, `blobs.lua`'s
  content kept once by id, `fold.lua`'s folds for the four disk keywords). A
  fresh tv-labs state per event costs about 0.4 ms, and alog's dozen
  statements from Elixir cost a dozen trips through Exqlite's dirty
  schedulers, which computers working at once queue for. The tests hold the
  trigger to alog: what it folded, alog's `rebuild` folds again exactly.

  Content is kept once by its SHA-256, as alog does with a host's digest; an
  id that names other bytes (a SHA-256 collision) stops the event rather than
  reuse them.
  """
  alias Moss.Db

  @recall 65_536

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

  # init.lua's record and fold.lua's folds, as one trigger: a1 and a2 are an event's first two arguments, id1/c1
  # and id2/c2 its content arguments' blob ids and bytes, words what recall_log indexes, ftext a written file's
  # recall text (blobs.lua's text); the new event is the newest seq.
  @append """
  create view if not exists moss_append_1 (at, task, keyword, actor, args, words, a1, a2, id1, c1, id2, c2, ftext) as
    select null, null, null, null, null, null, null, null, null, null, null, null, null where 0;
  create trigger if not exists moss_append_1_fold instead of insert on moss_append_1 begin
    select raise(abort, 'alog: a blob id names other bytes')
      where exists (select 1 from blobs where id = new.id1 and content is not new.c1)
         or exists (select 1 from blobs where id = new.id2 and content is not new.c2);
    insert or ignore into blobs (id, content) select new.id1, new.c1 where new.id1 is not null;
    insert or ignore into blobs (id, content) select new.id2, new.c2 where new.id2 is not null;
    insert into events (at, task, keyword, actor) values (new.at, new.task, new.keyword, new.actor);
    insert into args (seq, pos, value)
      select (select max(seq) from events), key + 1, value from json_each(new.args);
    insert into recall_log (rowid, keyword, args) values ((select max(seq) from events), new.keyword, new.words);

    insert or replace into files (path, dir, blob, seq)
      select new.a1, 0, new.id1, (select max(seq) from events) where new.keyword = 'Write File';
    delete from recall_files where new.keyword = 'Write File' and path = new.a1;
    insert into recall_files (path, content)
      select new.a1, new.ftext where new.keyword = 'Write File' and new.ftext is not null;

    insert or ignore into files (path, dir, blob, seq)
      select new.a1, 1, null, (select max(seq) from events) where new.keyword = 'Make Folder';

    delete from files where new.keyword = 'Delete File'
      and (path = new.a1 or substr(path, 1, length(new.a1) + 1) = new.a1 || '/');
    delete from recall_files where new.keyword = 'Delete File'
      and (path = new.a1 or substr(path, 1, length(new.a1) + 1) = new.a1 || '/');

    delete from files where new.keyword = 'Move File' and path = new.a2 and dir = 0;
    delete from recall_files where new.keyword = 'Move File' and path = new.a2;
    update files set path = new.a2 || substr(path, length(new.a1) + 1), seq = (select max(seq) from events)
      where new.keyword = 'Move File' and (path = new.a1 or substr(path, 1, length(new.a1) + 1) = new.a1 || '/');
    update recall_files set path = new.a2 || substr(path, length(new.a1) + 1)
      where new.keyword = 'Move File' and (path = new.a1 or substr(path, 1, length(new.a1) + 1) = new.a1 || '/');
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

    # content arguments by their blob id, the words recall indexes for each
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
    [{id1, c1}, {id2, c2}] = Enum.take(blobs ++ [{nil, nil}, {nil, nil}], 2)
    ftext = if keyword == "Write File", do: text(List.last(args))

    with {:ok, json} <- Jason.encode(kept),
         {:ok, _} <-
           Db.exec(
             conn,
             "insert into moss_append_1 values (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
             [at || clock(), task, keyword, actor, json, Enum.join(words, " ")] ++
               [Enum.at(args, 0), Enum.at(args, 1), id1, c1, id2, c2, ftext]
           ) do
      :ok
    else
      {:error, %Jason.EncodeError{}} -> {:error, "an argument is not UTF-8"}
      {:error, why} -> {:error, to_string(why)}
    end
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

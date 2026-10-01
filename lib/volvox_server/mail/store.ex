defmodule VolvoxServer.Mail.Store do
  @moduledoc """
  The post's SQLite file (Volvox PROJECT.md §14.5): every letter, the routes
  people set, and the senders Jev has refused. A letter's `state` is its place
  in the post, so the file is also the queue:

    * `screening`: on a screened route, waiting for Jev;
    * `delivered`: in the recipient's inbox (`audited` 0 until Jev has read it);
    * `held`: waiting for a person (Jev was unsure, or withdrew it unread);
    * `refused`: never delivered, `reason` says why.
  """
  alias VolvoxServer.Db

  @schema """
  create table if not exists letters(
    id integer primary key, sender text not null, recipient text not null, subject text not null,
    body text not null, at integer not null, state text not null, mode text not null,
    audited integer not null default 0, read integer not null default 0, verdict text, reason text);
  create index if not exists letters_inbox on letters(recipient, state);
  create index if not exists letters_sender on letters(sender, at);
  create index if not exists letters_waiting on letters(audited, state);
  create table if not exists routes(sender text not null, recipient text not null, mode text not null,
    primary key(sender, recipient));
  create table if not exists flagged(sender text primary key, at integer not null, reason text not null);
  """

  def open(path) do
    File.mkdir_p!(Path.dirname(path))

    with {:ok, conn} <- Db.open(path),
         {:ok, _} <- Db.exec(conn, @schema, []),
         do: {:ok, conn}
  end

  def put(conn, l) do
    {:ok, [%{"id" => id}]} =
      Db.exec(
        conn,
        "insert into letters(sender, recipient, subject, body, at, state, mode, audited, reason) " <>
          "values (?, ?, ?, ?, ?, ?, ?, ?, ?) returning id",
        [l.sender, l.recipient, l.subject, l.body, now(), l.state, l.mode, l.audited, l[:reason]]
      )

    id
  end

  def get(conn, id), do: one(conn, "select * from letters where id = ?", [id])

  def set(conn, id, fields) do
    {cols, vals} = Enum.unzip(fields)
    sets = Enum.map_join(cols, ", ", &"#{&1} = ?")
    {:ok, _} = Db.exec(conn, "update letters set #{sets} where id = ?", vals ++ [id])
    :ok
  end

  def inbox(conn, agent),
    do:
      all(
        conn,
        "select * from letters where recipient = ? and state = 'delivered' order by id",
        [agent]
      )

  def sent(conn, agent),
    do: all(conn, "select * from letters where sender = ? order by id", [agent])

  def recent(conn, limit \\ 100),
    do: all(conn, "select * from letters order by id desc limit ?", [limit])

  @doc "Letters Jev has yet to read: screened ones waiting, delivered ones unaudited."
  def waiting(conn, limit),
    do:
      all(
        conn,
        "select * from letters where state = 'screening' or (state = 'delivered' and audited = 0) " <>
          "order by id limit ?",
        [limit]
      )

  @doc "What a sender sent before `id`, newest first: the history Jev reads a letter against."
  def before(conn, sender, id, limit),
    do:
      all(
        conn,
        "select id, recipient, subject, state, verdict from letters where sender = ? and id < ? " <>
          "order by id desc limit ?",
        [sender, id, limit]
      )

  def sent_since(conn, sender, since) do
    {:ok, [%{"n" => n}]} =
      Db.exec(conn, "select count(*) as n from letters where sender = ? and at >= ?", [
        sender,
        since
      ])

    n
  end

  # -- routes and flags ---------------------------------------------------------------------------

  def route(conn, sender, recipient, mode) do
    {:ok, _} =
      Db.exec(
        conn,
        "insert into routes values (?, ?, ?) on conflict(sender, recipient) do update set mode = excluded.mode",
        [sender, recipient, mode]
      )

    :ok
  end

  def unroute(conn, sender, recipient) do
    {:ok, _} =
      Db.exec(conn, "delete from routes where sender = ? and recipient = ?", [sender, recipient])

    :ok
  end

  def routes(conn), do: all(conn, "select * from routes order by sender, recipient", [])

  @doc "The route's mode, the exact route before a wildcard (`*`) one; nil when none allows it."
  def mode(conn, sender, recipient) do
    case one(
           conn,
           "select mode from routes where sender in (?, '*') and recipient in (?, '*') " <>
             "order by (sender = '*') + (recipient = '*') limit 1",
           [sender, recipient]
         ) do
      %{"mode" => mode} -> mode
      nil -> nil
    end
  end

  def flag(conn, sender, reason) do
    {:ok, _} =
      Db.exec(conn, "insert or replace into flagged values (?, ?, ?)", [sender, now(), reason])

    :ok
  end

  def unflag(conn, sender) do
    {:ok, _} = Db.exec(conn, "delete from flagged where sender = ?", [sender])
    :ok
  end

  def flagged(conn), do: all(conn, "select * from flagged order by at desc", [])

  def flagged?(conn, sender),
    do: one(conn, "select 1 as f from flagged where sender = ?", [sender]) != nil

  def now, do: System.os_time(:millisecond)

  defp all(conn, sql, params) do
    {:ok, rows} = Db.exec(conn, sql, params)
    rows
  end

  defp one(conn, sql, params), do: conn |> all(sql, params) |> List.first()
end

defmodule VolvoxServer.Mail do
  @moduledoc """
  The post between agents' computers (Volvox PROJECT.md §14.5). Agents talk
  only by mail: an address is the agent's computer id, and a letter travels
  only along a route a person set (`route(sender, recipient, mode)`, either
  side may be `*`). One process per node holds the post's SQLite file
  (`Mail.Store`), so a letter outlives a restart.

      Mail.route("rock-1", "rock-2", "audit")
      Mail.post("rock-1", "rock-2", "fern", "the fern needs water")
      #=> {:delivered, 1}

  Every letter passes the free checks (`Mail.Checks`) at once. Then Jev reads
  it (`Mail.Screen`), in batches of up to #{32} or whatever #{2} s gathered: on an
  `audit` route the letter is delivered first and read after; on a `screen`
  route, or from a sender Jev has refused, it waits for Jev. Delivery is
  broadcast on `mail:<recipient>`, every change on `mail`.
  """
  use GenServer
  require Logger
  alias VolvoxServer.Mail.{Checks, Screen, Store}

  @batch 32

  def post(sender, recipient, subject, body),
    do: GenServer.call(__MODULE__, {:post, sender, recipient, subject, body})

  def inbox(agent), do: GenServer.call(__MODULE__, {:inbox, agent})
  def sent(agent), do: GenServer.call(__MODULE__, {:sent, agent})
  def read(agent, id), do: GenServer.call(__MODULE__, {:read, agent, id})
  def recent(limit \\ 100), do: GenServer.call(__MODULE__, {:recent, limit})
  def routes, do: GenServer.call(__MODULE__, :routes)
  def flagged, do: GenServer.call(__MODULE__, :flagged)

  def route(sender, recipient, mode) when mode in ["audit", "screen"],
    do: GenServer.call(__MODULE__, {:route, sender, recipient, mode})

  def unroute(sender, recipient), do: GenServer.call(__MODULE__, {:unroute, sender, recipient})
  def unflag(sender), do: GenServer.call(__MODULE__, {:unflag, sender})

  @doc "A person's word on a held letter: release delivers it, refuse keeps it from the recipient."
  def release(id),
    do: GenServer.call(__MODULE__, {:decide, id, "delivered", "released by a person"})

  def refuse(id), do: GenServer.call(__MODULE__, {:decide, id, "refused", "refused by a person"})

  @doc "Has Jev read every waiting letter now, batch after batch, before answering."
  def screen_now, do: GenServer.call(__MODULE__, :screen_now, :infinity)

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  # -- the process -------------------------------------------------------------------------------

  @impl true
  def init(opts) do
    path =
      opts[:path] ||
        Path.join(Application.fetch_env!(:volvox_server, :work_dir), "mail.sqlite")

    {:ok, conn} = Store.open(path)
    # letters that waited through a restart are read first
    send(self(), :screen)
    {:ok, %{conn: conn, timer: nil, asking: nil, wait: 0}}
  end

  @impl true
  def handle_call({:post, sender, recipient, subject, body}, _from, s) do
    case Checks.letter(s.conn, sender, recipient, subject, body) do
      {:refused, reason} ->
        Store.put(s.conn, %{
          sender: sender,
          recipient: recipient,
          subject: subject,
          body: body,
          state: "refused",
          mode: "checks",
          audited: 1,
          reason: reason
        })

        changed()
        {:reply, {:refused, reason}, s}

      {:ok, mode} ->
        state = if mode == "audit", do: "delivered", else: "screening"

        id =
          Store.put(s.conn, %{
            sender: sender,
            recipient: recipient,
            subject: subject,
            body: body,
            state: state,
            mode: mode,
            audited: 0
          })

        if state == "delivered", do: delivered(recipient, id), else: changed()
        {:reply, {String.to_atom(state), id}, soon(s)}
    end
  end

  def handle_call({:inbox, agent}, _from, s), do: {:reply, Store.inbox(s.conn, agent), s}
  def handle_call({:sent, agent}, _from, s), do: {:reply, Store.sent(s.conn, agent), s}
  def handle_call({:recent, n}, _from, s), do: {:reply, Store.recent(s.conn, n), s}
  def handle_call(:routes, _from, s), do: {:reply, Store.routes(s.conn), s}
  def handle_call(:flagged, _from, s), do: {:reply, Store.flagged(s.conn), s}

  def handle_call({:read, agent, id}, _from, s) do
    case Store.get(s.conn, id) do
      %{"recipient" => ^agent, "state" => "delivered"} = l ->
        :ok = Store.set(s.conn, id, read: 1)
        {:reply, {:ok, l}, s}

      _ ->
        {:reply, :none, s}
    end
  end

  def handle_call({:route, from, to, mode}, _from, s),
    do: {:reply, tap(Store.route(s.conn, from, to, mode), fn _ -> changed() end), s}

  def handle_call({:unroute, from, to}, _from, s),
    do: {:reply, tap(Store.unroute(s.conn, from, to), fn _ -> changed() end), s}

  def handle_call({:unflag, sender}, _from, s),
    do: {:reply, tap(Store.unflag(s.conn, sender), fn _ -> changed() end), s}

  def handle_call({:decide, id, state, reason}, _from, s) do
    case Store.get(s.conn, id) do
      %{"state" => "held"} = l ->
        :ok = Store.set(s.conn, id, state: state, reason: reason, audited: 1)
        if state == "delivered", do: delivered(l["recipient"], id), else: changed()
        {:reply, :ok, s}

      _ ->
        {:reply, {:error, "only a held letter waits for a person"}, s}
    end
  end

  def handle_call(:screen_now, _from, s) do
    {:reply, drain(s.conn), s}
  end

  @impl true
  def handle_info(:screen, %{asking: nil} = s) do
    case Store.waiting(s.conn, @batch) do
      [] ->
        {:noreply, %{s | timer: nil}}

      letters ->
        me = self()
        conn = s.conn

        {:ok, pid} =
          Task.start(fn -> send(me, {:answered, letters, Screen.ask(letters, conn)}) end)

        {:noreply, %{s | timer: nil, asking: pid}}
    end
  end

  def handle_info(:screen, s), do: {:noreply, %{s | timer: nil}}

  def handle_info({:answered, letters, result}, s) do
    s = %{s | asking: nil}

    case result do
      {:ok, answers} ->
        settle(s.conn, letters, answers)
        {:noreply, soon(%{s | wait: 0})}

      {:error, why} ->
        # Jev is unreachable: the letters keep waiting (screened ones undelivered) and the post asks again later
        wait = min(max(s.wait * 2, 5_000), 300_000)
        Logger.warning("mail: Jev did not answer (#{why}); asking again in #{div(wait, 1000)} s")
        {:noreply, %{s | wait: wait, timer: Process.send_after(self(), :screen, wait)}}
    end
  end

  # the next batch in the window, unless one is already coming or being read
  defp soon(%{timer: nil, asking: nil} = s),
    do: %{s | timer: Process.send_after(self(), :screen, window())}

  defp soon(s), do: s

  defp drain(conn) do
    case Store.waiting(conn, @batch) do
      [] ->
        :ok

      letters ->
        case Screen.ask(letters, conn) do
          {:ok, answers} ->
            settle(conn, letters, answers)
            drain(conn)

          {:error, why} ->
            {:error, why}
        end
    end
  end

  defp settle(conn, letters, answers) do
    # read again: a person, or another batch, may have settled a letter while Jev was reading it
    for %{"id" => id} <- letters, l = Store.get(conn, id), l["audited"] == 0 do
      now = Screen.apply(conn, l, answers["l#{id}"])
      if l["state"] != "delivered" and now == "delivered", do: delivered(l["recipient"], id)
    end

    changed()
  end

  defp delivered(recipient, id) do
    Phoenix.PubSub.broadcast(VolvoxServer.PubSub, "mail:" <> recipient, {:mail, id})
    changed()
  end

  defp changed, do: Phoenix.PubSub.broadcast(VolvoxServer.PubSub, "mail", :mail_changed)
  defp window, do: Application.get_env(:volvox_server, :mail_window, 2_000)
end

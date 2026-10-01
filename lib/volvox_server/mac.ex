defmodule VolvoxServer.Mac do
  @moduledoc """
  Work only the person's Mac can do (its apps, its screen), handed from a
  rock to the Pet Rock app over the `mac:<owner>` channel
  (`VolvoxServerWeb.MacChannel`). The node's own book, `mac.sqlite` under
  `host_dir`, holds each piece of work until the Mac says it is done, so
  nothing is lost when the Mac or the node goes away.

    * `need(owner, run, task, request)`: sent at once when the owner's Mac is
      online (the run logs the host's `Sent To Mac <request>`); otherwise it
      waits, the run logs `Waiting For Mac <request>` and the rock says so.
    * When the Mac joins, everything it has not finished is sent; when it
      leaves, what it had not finished waits again.
    * `done(owner, id, result)`: the run logs `Mac Result <request> <result>`.

  The Mac gets `{:work, %{id, run, task, request}}` as a message to its
  channel process.
  """
  use GenServer

  alias VolvoxServer.{Db, Run}

  @waiting "My Mac hands are offline, so this waits until the Mac app is back; I'll do it then."

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  def need(owner, run, task, request),
    do: GenServer.call(__MODULE__, {:need, owner, run, task, request})

  def online(owner), do: GenServer.call(__MODULE__, {:online, owner, self()})
  def done(owner, id, result), do: GenServer.call(__MODULE__, {:done, owner, id, result})
  def waiting(owner), do: GenServer.call(__MODULE__, {:waiting, owner})

  @schema """
  create table if not exists work (
    id integer primary key, owner text not null, run text not null, task text not null,
    request text not null, sent integer not null default 0
  );
  """

  @impl true
  def init(nil) do
    dir = Application.fetch_env!(:volvox_server, :host_dir)
    File.mkdir_p!(dir)
    {:ok, conn} = Db.open(Path.join(dir, "mac.sqlite"))
    {:ok, []} = Db.exec(conn, @schema <> "update work set sent = 0;", [])
    {:ok, %{conn: conn, macs: %{}}}
  end

  @impl true
  def handle_call({:need, owner, run, task, request}, _from, state) do
    sql = "insert into work (owner, run, task, request) values (?, ?, ?, ?) returning id"
    {:ok, [%{"id" => id}]} = Db.exec(state.conn, sql, [owner, run, task, request])
    work = %{id: id, run: run, task: task, request: request}

    result =
      case state.macs[owner] do
        nil ->
          log(run, task, [{"Waiting For Mac", [request], "host"}, {"Say", [@waiting], "agent"}])

        pid ->
          send_work(state.conn, pid, work)
      end

    {:reply, with(:ok <- result, do: {:ok, id}), state}
  end

  def handle_call({:online, owner, pid}, _from, state) do
    Process.monitor(pid)
    {:ok, rows} = Db.exec(state.conn, "select * from work where owner = ? order by id", [owner])
    for r <- rows, do: send_work(state.conn, pid, work(r))
    {:reply, :ok, %{state | macs: Map.put(state.macs, owner, pid)}}
  end

  def handle_call({:done, owner, id, result}, _from, state) do
    sql = "delete from work where id = ? and owner = ? returning run, task, request"

    case Db.exec(state.conn, sql, [id, owner]) do
      {:ok, [r]} ->
        {:reply, log(r["run"], r["task"], [{"Mac Result", [r["request"], result], "host"}]),
         state}

      {:ok, []} ->
        {:reply, {:error, "no work #{id} for this Mac"}, state}
    end
  end

  def handle_call({:waiting, owner}, _from, state) do
    sql = "select * from work where owner = ? and sent = 0 order by id"
    {:ok, rows} = Db.exec(state.conn, sql, [owner])
    {:reply, Enum.map(rows, &work/1), state}
  end

  @impl true
  def handle_info({:DOWN, _, :process, pid, _}, state) do
    case Enum.find(state.macs, fn {_, p} -> p == pid end) do
      {owner, _} ->
        {:ok, _} = Db.exec(state.conn, "update work set sent = 0 where owner = ?", [owner])
        {:noreply, %{state | macs: Map.delete(state.macs, owner)}}

      nil ->
        {:noreply, state}
    end
  end

  defp send_work(conn, pid, work) do
    send(pid, {:work, work})
    {:ok, _} = Db.exec(conn, "update work set sent = 1 where id = ?", [work.id])
    log(work.run, work.task, [{"Sent To Mac", [work.request], "host"}])
  end

  defp work(r), do: %{id: r["id"], run: r["run"], task: r["task"], request: r["request"]}

  # The run wakes if it sleeps, so its log says where the work is.
  defp log(run, task, events) do
    with {:ok, _} <- Run.wake(run) do
      Enum.reduce_while(events, :ok, fn {keyword, args, actor}, :ok ->
        case Run.append(run, task, keyword, args, actor) do
          {:ok, _} -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)
    end
  end
end

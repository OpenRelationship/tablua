defmodule VolvoxServer.Schedule do
  @moduledoc """
  Jobs that wake a run at a time and drive a task in it (`Run.drive/4`): the
  node's own book, one SQLite file `schedule.sqlite` under `host_dir`, so the
  schedule outlives the node. Every `tick_ms` the jobs that are due fire; a job
  missed while the node was down fires once on the first tick after it is up.

    * `add(run, task, goal, agent, at, every \\\\ nil)`: at a `DateTime`, and
      again every `every` seconds when given. Each firing drives a task named
      `<task>-<unix time it was due>` in the run.
    * `jobs/0`, `remove/1`, `fired/1` (the firings of a job: due, fired, and
      the error if it did not start).

  Each firing is broadcast on PubSub `schedule` as `{:fired, job, due, fired}`.
  """
  use GenServer

  alias VolvoxServer.{Db, Run}

  def start_link(_), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  def add(run, task, goal, agent, %DateTime{} = at, every \\ nil),
    do: GenServer.call(__MODULE__, {:add, [run, task, goal, agent, DateTime.to_unix(at), every]})

  def jobs, do: GenServer.call(__MODULE__, :jobs)
  def remove(job), do: GenServer.call(__MODULE__, {:remove, job})
  def fired(job), do: GenServer.call(__MODULE__, {:fired, job})

  @schema """
  create table if not exists jobs (
    id integer primary key, run text not null, task text not null, goal text not null,
    agent text not null, at integer not null, every integer
  );
  create table if not exists fired (
    job integer not null, due integer not null, fired integer not null, error text
  );
  """

  @impl true
  def init(nil) do
    dir = Application.fetch_env!(:volvox_server, :host_dir)
    File.mkdir_p!(dir)
    {:ok, conn} = Db.open(Path.join(dir, "schedule.sqlite"))
    {:ok, []} = Db.exec(conn, @schema, [])
    send(self(), :tick)
    {:ok, %{conn: conn, tick: Application.fetch_env!(:volvox_server, :tick_ms)}}
  end

  @impl true
  def handle_call({:add, [run, task, _, _, _, every] = row}, _from, state) do
    cond do
      not (is_binary(run) and run =~ ~r/^[A-Za-z0-9_-]{1,64}$/) ->
        {:reply, {:error, "a run id is 1-64 letters, digits, - or _"}, state}

      not (is_binary(task) and task =~ ~r/^[A-Za-z0-9_.:-]{1,40}$/) ->
        {:reply, {:error, "a task is a plain name"}, state}

      every != nil and not (is_integer(every) and every >= 60) ->
        {:reply, {:error, "a job repeats every 60 seconds or more"}, state}

      true ->
        {:ok, [%{"id" => id}]} =
          Db.exec(
            state.conn,
            "insert into jobs (run, task, goal, agent, at, every) values (?, ?, ?, ?, ?, ?) returning id",
            row
          )

        {:reply, {:ok, id}, state}
    end
  end

  def handle_call(:jobs, _from, state) do
    {:ok, rows} = Db.exec(state.conn, "select * from jobs order by at", [])
    {:reply, Enum.map(rows, &atomize/1), state}
  end

  def handle_call({:remove, job}, _from, state) do
    {:ok, _} = Db.exec(state.conn, "delete from jobs where id = ?", [job])
    {:reply, :ok, state}
  end

  def handle_call({:fired, job}, _from, state) do
    {:ok, rows} = Db.exec(state.conn, "select * from fired where job = ? order by due", [job])
    {:reply, Enum.map(rows, &atomize/1), state}
  end

  @impl true
  def handle_info(:tick, state) do
    now = System.os_time(:second)
    {:ok, due} = Db.exec(state.conn, "select * from jobs where at <= ? order by at", [now])
    Enum.each(due, &fire(state.conn, atomize(&1), now))
    Process.send_after(self(), :tick, state.tick)
    {:noreply, state}
  end

  def handle_info({:started, job, due, result}, state) do
    error = with {:error, reason} <- result, do: inspect(reason)
    fired = System.os_time(:second)
    sql = "insert into fired (job, due, fired, error) values (?, ?, ?, ?)"
    {:ok, _} = Db.exec(state.conn, sql, [job, due, fired, if(error == :ok, do: nil, else: error)])
    Phoenix.PubSub.broadcast(VolvoxServer.PubSub, "schedule", {:fired, job, due, fired})
    {:noreply, state}
  end

  # The job moves on before its task starts, so a slow run never fires it twice. A repeating job
  # skips the times it missed while the node was down: it fires once, then keeps its rhythm.
  defp fire(conn, job, now) do
    case Map.get(job, :every) do
      nil ->
        {:ok, _} = Db.exec(conn, "delete from jobs where id = ?", [job.id])

      every ->
        next = job.at + every * (div(now - job.at, every) + 1)
        {:ok, _} = Db.exec(conn, "update jobs set at = ? where id = ?", [next, job.id])
    end

    me = self()
    task = "#{job.task}-#{job.at}"

    Task.start(fn ->
      result =
        with {:ok, _} <- Run.wake(job.run), do: Run.drive(job.run, task, job.goal, job.agent)

      send(me, {:started, job.id, job.at, result})
    end)
  end

  # NULL columns come back absent (VolvoxServer.Db): every and error are nil then.
  defp atomize(row),
    do:
      Map.merge(
        %{every: nil, error: nil},
        Map.new(row, fn {k, v} -> {String.to_existing_atom(k), v} end)
      )
end

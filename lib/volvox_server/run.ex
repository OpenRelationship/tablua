defmodule VolvoxServer.Run do
  @moduledoc """
  One Volvox run: one supervised process holding the connection to the run's
  SQLite file, and nothing else. The file is the run's log, workspace and
  state; the Lua state is built fresh for every call and dropped after it.

    * wake: the process starts. If a working copy of the file is on this node
      (the run was killed while awake) it is opened as it is, since it is newer
      than anything uploaded; otherwise `runs/<id>.sqlite` is pulled from the
      object store, or a new file is made for a new run.
    * `start_task/3`, `step/2`, `append/5`: one core call each. Each new event
      is then broadcast on PubSub `run:<id>` as `{:event, event}`, followed by
      `{:tasks, tasks}`.
    * sleep: the WAL is checkpointed into the file, the file closed and
      uploaded, the working copy removed and the process stopped.

  Runs are registered by id in `VolvoxServer.Run.Registry` and supervised by
  `VolvoxServer.Run.Supervisor` with restart `:transient`, so a crashed or
  killed run comes back from its file and a slept one stays down.

  Options: `agent:` the agent's Lua source, a function(host) returning the
  coordinator's options without the store (see `priv/lua/host.lua`). A run
  woken only to be watched needs none.
  """
  use GenServer, restart: :transient

  alias VolvoxServer.{Db, Objects}
  alias VolvoxServer.Run.Log

  @registry VolvoxServer.Run.Registry

  def wake(id, opts \\ []) do
    check_id!(id)

    case DynamicSupervisor.start_child(VolvoxServer.Run.Supervisor, {__MODULE__, {id, opts}}) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc "The run's process, if it is awake (a just-stopped one may linger in the registry)."
  def whereis(id) do
    case Registry.lookup(@registry, id) do
      [{pid, _}] -> if Process.alive?(pid), do: pid
      [] -> nil
    end
  end

  def start_task(id, task, goal), do: call(id, {:core, :start, [task, goal], true})
  def step(id, task), do: call(id, {:core, :step, [task], true})

  def append(id, task, keyword, args, actor \\ "user"),
    do: call(id, {:core, :append, [task, keyword, args, actor], false})

  def dump(id), do: call(id, {:core, :dump, [], false})
  def robot(id), do: call(id, {:core, :robot, [], false})
  def snapshot(id), do: call(id, :snapshot)
  def sleep(id), do: call(id, :sleep)

  defp call(id, msg), do: GenServer.call(via(id), msg, :infinity)

  defp via(id), do: {:via, Registry, {@registry, id}}

  defp check_id!(id) do
    unless is_binary(id) and id =~ ~r/^[A-Za-z0-9_-]{1,64}$/,
      do: raise(ArgumentError, "a run id is 1-64 letters, digits, - or _: #{inspect(id)}")
  end

  def start_link({id, opts}), do: GenServer.start_link(__MODULE__, {id, opts}, name: via(id))

  @impl true
  def init({id, opts}) do
    path = Path.join(Application.fetch_env!(:volvox_server, :work_dir), id <> ".sqlite")
    File.mkdir_p!(Path.dirname(path))

    with :ok <- pull(id, path),
         {:ok, conn} <- Db.open(path),
         {:ok, _} <- VolvoxServer.Lua.call(:open, [], db: conn) do
      agent = opts[:agent] && VolvoxServer.Lua.agent!(opts[:agent])
      {:ok, %{id: id, path: path, conn: conn, agent: agent, seq: Log.last_seq(conn)}}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  defp pull(id, path) do
    if File.exists?(path) do
      :ok
    else
      case Objects.get(Objects.run_key(id)) do
        {:ok, body} -> File.write(path, body)
        :not_found -> :ok
        {:error, reason} -> {:error, {:pull, reason}}
      end
    end
  end

  @impl true
  def handle_call({:core, _fun, _args, true}, _from, %{agent: nil} = state) do
    {:reply, {:error, "run #{state.id} was woken without an agent"}, state}
  end

  def handle_call({:core, fun, args, agent?}, _from, state) do
    opts = if agent?, do: [agent: state.agent], else: []
    result = VolvoxServer.Lua.call(fun, args, [db: state.conn], opts)
    {:reply, unwrap(result), broadcast(state)}
  end

  def handle_call(:snapshot, _from, state) do
    {:reply, %{events: Log.after_seq(state.conn, 0), tasks: Log.tasks(state.conn)}, state}
  end

  def handle_call(:sleep, _from, state) do
    with :ok <- Db.checkpoint_and_close(state.conn),
         {:ok, body} <- File.read(state.path),
         :ok <- Objects.put(Objects.run_key(state.id), body) do
      for suffix <- ["", "-wal", "-shm"], do: File.rm(state.path <> suffix)
      {:stop, :normal, :ok, %{state | conn: nil}}
    else
      error -> {:stop, {:sleep_failed, error}, error, state}
    end
  end

  defp unwrap({:ok, [one]}), do: {:ok, one}
  defp unwrap({:ok, many}), do: {:ok, List.to_tuple(many)}
  defp unwrap(error), do: error

  # Every event past the last one broadcast, then the tasks as they now stand.
  defp broadcast(state) do
    case Log.after_seq(state.conn, state.seq) do
      [] ->
        state

      events ->
        topic = "run:" <> state.id
        for e <- events, do: Phoenix.PubSub.broadcast(VolvoxServer.PubSub, topic, {:event, e})
        Phoenix.PubSub.broadcast(VolvoxServer.PubSub, topic, {:tasks, Log.tasks(state.conn)})
        %{state | seq: List.last(events).seq}
    end
  end
end

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

  `drive/4` starts a task the run then steps by itself, one step a message, so
  calls still come between steps. It names its agent (`VolvoxServer.Agents`)
  in the log as the host's `Drive Task <agent>` and ends with `Drive Done
  <state>`; a run that wakes with a task driven and not done (after a kill, or
  from its working copy when the node restarts, `wake_working/0`) goes on
  stepping it from the state its log holds. A driving run does not sleep.

  A run with nothing to do sleeps by itself after `idle_ms` (option, else the
  config's): asleep it is only its file in the object store, with no process.
  """
  use GenServer, restart: :transient

  alias VolvoxServer.{Agents, Db, Objects}
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

  def drive(id, task, goal, agent), do: call(id, {:drive, task, goal, agent})

  def dump(id), do: call(id, {:core, :dump, [], false})
  def robot(id), do: call(id, {:core, :robot, [], false})
  def snapshot(id), do: call(id, :snapshot)
  def sleep(id), do: call(id, :sleep)

  @doc "Wakes every run with a working copy on this node: those awake when it stopped."
  def wake_working do
    dir = Application.fetch_env!(:volvox_server, :work_dir)

    for file <- File.ls!(dir), Path.extname(file) == ".sqlite" do
      id = Path.rootname(file)
      {id, wake(id)}
    end
  rescue
    File.Error -> []
  end

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
         {:ok, _} <- VolvoxServer.Lua.call(:open, [], db: conn, computer: id) do
      agent = opts[:agent] && VolvoxServer.Lua.agent!(opts[:agent])
      driving = Log.driving(conn)
      for {task, name} <- driving, do: send(self(), {:drive, task, name})
      idle = opts[:idle_ms] || Application.get_env(:volvox_server, :idle_ms, 300_000)
      Process.send_after(self(), :idle, idle)

      {:ok,
       %{
         id: id,
         path: path,
         conn: conn,
         agent: agent,
         seq: Log.last_seq(conn),
         driving: MapSet.new(driving, &elem(&1, 0)),
         idle: idle,
         touched: now()
       }}
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
    result = VolvoxServer.Lua.call(fun, args, [db: state.conn, computer: state.id], opts)
    # Each call's Lua state is garbage once it returns: hibernating drops it, so an awake run
    # holds only its connection between calls.
    {:reply, unwrap(result), broadcast(state), :hibernate}
  end

  def handle_call({:drive, task, goal, name}, _from, state) do
    db = [db: state.conn, computer: state.id]

    with {:ok, agent} <- Agents.chunk(name),
         {:ok, _} <- VolvoxServer.Lua.call(:start, [task, goal], db, agent: agent),
         {:ok, _} <- VolvoxServer.Lua.call(:append, [task, "Drive Task", [name], "host"], db) do
      send(self(), {:drive, task, name})
      {:reply, :ok, broadcast(%{state | driving: MapSet.put(state.driving, task)})}
    else
      error -> {:reply, error, broadcast(state)}
    end
  end

  def handle_call(:snapshot, _from, state) do
    {:reply, %{events: Log.after_seq(state.conn, 0), tasks: Log.tasks(state.conn)}, state}
  end

  def handle_call(:sleep, _from, state) do
    if MapSet.size(state.driving) > 0 do
      {:reply, {:error, "run #{state.id} is driving #{Enum.join(state.driving, ", ")}"}, state}
    else
      case sleep_now(state) do
        {:ok, state} -> {:stop, :normal, :ok, state}
        {error, state} -> {:stop, {:sleep_failed, error}, error, state}
      end
    end
  end

  defp sleep_now(state) do
    with :ok <- Db.checkpoint_and_close(state.conn),
         {:ok, body} <- File.read(state.path),
         :ok <- Objects.put(Objects.run_key(state.id), body) do
      for suffix <- ["", "-wal", "-shm"], do: File.rm(state.path <> suffix)
      {:ok, %{state | conn: nil}}
    else
      error -> {error, state}
    end
  end

  @impl true
  def handle_info(:idle, state) do
    left = state.touched + state.idle - now()

    cond do
      MapSet.size(state.driving) > 0 or left > 0 ->
        Process.send_after(self(), :idle, if(left > 0, do: left, else: state.idle))
        {:noreply, state}

      true ->
        case sleep_now(state) do
          {:ok, state} -> {:stop, :normal, state}
          {error, state} -> {:stop, {:sleep_failed, error}, state}
        end
    end
  end

  def handle_info({:drive, task, name}, state) do
    db = [db: state.conn, computer: state.id]

    result =
      with {:ok, agent} <- Agents.chunk(name),
           do: VolvoxServer.Lua.call(:step, [task], db, agent: agent)

    done =
      case result do
        {:ok, [_state, false]} -> nil
        {:ok, [now, true]} -> [now]
        {:error, message} -> ["error", message]
      end

    if done do
      VolvoxServer.Lua.call(:append, [task, "Drive Done", done, "host"], db)
      {:noreply, broadcast(%{state | driving: MapSet.delete(state.driving, task)}), :hibernate}
    else
      send(self(), {:drive, task, name})
      {:noreply, broadcast(state)}
    end
  end

  defp unwrap({:ok, [one]}), do: {:ok, one}
  defp unwrap({:ok, many}), do: {:ok, List.to_tuple(many)}
  defp unwrap(error), do: error

  defp now, do: System.monotonic_time(:millisecond)

  # Every event past the last one broadcast, then the tasks as they now stand. Anything that
  # writes the log comes through here, so it is also when the run was last busy.
  defp broadcast(state) do
    state = %{state | touched: now()}

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

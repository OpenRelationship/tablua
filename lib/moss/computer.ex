defmodule Moss.Computer do
  @moduledoc """
  An agent's own computer (Arock's PROJECT.md §14): one process per agent,
  whose disk is its own SQLite file (`Computer.Disk`), whose shell
  (`Computer.Shell`) runs its commands and its Lua (`Computer.Script`) here in
  the BEAM, and whose browser
  (`Computer.Browser`) keeps its pages headless. Nothing it does reaches the
  node's files, a real shell, or another agent's computer.

      Computer.run("rock-7", "mkdir -p notes && echo hi > notes/a.txt && cat notes/a.txt")
      #=> %{out: "hi\\n", err: "", code: 0, cwd: "/home"}

  Asleep, the computer is its file in the object store (`computers/<id>.sqlite`);
  `run` wakes it. It sleeps by itself after `idle_ms` with nothing to do. Every
  command is broadcast on `computer:<id>` for a person watching
  (`ComputerLive`).
  """
  use GenServer
  alias Moss.{Db, Objects}
  alias Moss.Computer.{Browser, Disk, Shell}

  @registry Moss.Computer.Registry
  @lines 200

  def run(id, line), do: GenServer.call(wake!(id), {:run, line}, :infinity)

  @doc """
  The core's exec port (`ports.box`'s contract) on this computer: `files` are
  written first (path => content, relative to `cwd`), then `cmd` runs in `cwd`.
  """
  def exec(id, %{} = req) do
    cwd = req["cwd"] || "/home"

    with :ok <- GenServer.call(wake!(id), {:files, cwd, req["files"] || %{}}) do
      r = run(id, "cd '#{String.replace(cwd, "'", "")}' && " <> (req["cmd"] || "true"))
      %{"code" => r.code, "stdout" => r.out, "stderr" => r.err, "timed_out" => false}
    else
      {:error, why} ->
        %{
          "code" => 2,
          "stdout" => "",
          "stderr" => "a file could not be written: #{why}\n",
          "timed_out" => false
        }
    end
  end

  def view(id), do: GenServer.call(wake!(id), :view)
  def sleep(id), do: if(pid = whereis(id), do: GenServer.call(pid, :sleep), else: :ok)

  def whereis(id) do
    case Registry.lookup(@registry, id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  def wake!(id, opts \\ []) do
    case DynamicSupervisor.start_child(Moss.Computer.Supervisor, %{
           id: {__MODULE__, id},
           start:
             {GenServer, :start_link,
              [__MODULE__, {id, opts}, [name: {:via, Registry, {@registry, id}}]]},
           restart: :transient
         }) do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
      {:error, reason} -> raise "computer #{id} would not wake: #{inspect(reason)}"
    end
  end

  # -- the process -------------------------------------------------------------------------------

  @impl true
  def init({id, opts}) do
    path =
      Path.join([Application.fetch_env!(:moss, :work_dir), "computers", id <> ".sqlite"])

    File.mkdir_p!(Path.dirname(path))

    with :ok <- pull(id, path),
         {:ok, disk} <- Disk.open(path) do
      :ok = Disk.mkdir_p(disk, "/home")
      :ok = Disk.mkdir_p(disk, "/tmp")
      idle = opts[:idle_ms] || Application.get_env(:moss, :idle_ms, 300_000)
      Process.send_after(self(), :idle, idle)
      kept = Disk.kept(disk, "session", %{})

      {:ok,
       %{
         id: id,
         path: path,
         disk: disk,
         cwd: Map.get(kept, :cwd, "/home"),
         env: Map.get(kept, :env, %{"HOME" => "/home", "USER" => "agent", "PATH" => "/bin"}),
         last_code: 0,
         browser: Map.get(kept, :browser, Browser.new()),
         lines: Map.get(kept, :lines, []),
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
      case Objects.get(Objects.computer_key(id)) do
        {:ok, body} -> File.write(path, body)
        :not_found -> :ok
        {:error, reason} -> {:error, {:pull, reason}}
      end
    end
  end

  @impl true
  def handle_call({:run, line}, _from, state) do
    started = System.monotonic_time(:microsecond)
    {r, state} = Shell.run(line, state)
    ms = (System.monotonic_time(:microsecond) - started) / 1000
    entry = %{line: line, out: r.out, err: r.err, code: r.code, cwd: state.cwd, ms: ms}

    state = %{
      state
      | last_code: r.code,
        lines: Enum.take([entry | state.lines], @lines),
        touched: now()
    }

    keep(state)

    Phoenix.PubSub.broadcast(
      Moss.PubSub,
      "computer:#{state.id}",
      {:computer, state.id, entry}
    )

    {:reply, Map.put(r, :cwd, state.cwd), state, :hibernate}
  end

  def handle_call({:files, cwd, files}, _from, state) do
    :ok = Disk.mkdir_p(state.disk, Disk.norm(cwd))

    result =
      Enum.reduce_while(files, :ok, fn {path, body}, :ok ->
        case Disk.write(state.disk, Disk.norm(path, Disk.norm(cwd)), body) do
          :ok -> {:cont, :ok}
          {:error, e} -> {:halt, {:error, "#{path}: #{e}"}}
        end
      end)

    {:reply, result, state}
  end

  def handle_call(:view, _from, state) do
    {:reply,
     %{
       id: state.id,
       cwd: state.cwd,
       lines: Enum.reverse(state.lines),
       browser: state.browser,
       files: Disk.list(state.disk, state.cwd)
     }, state}
  end

  def handle_call(:sleep, _from, state) do
    case sleep_now(state) do
      :ok -> {:stop, :normal, :ok, %{state | disk: nil}}
      error -> {:reply, error, state}
    end
  end

  @impl true
  def handle_info(:idle, state) do
    left = state.touched + state.idle - now()

    if left > 0 do
      Process.send_after(self(), :idle, left)
      {:noreply, state, :hibernate}
    else
      case sleep_now(state) do
        :ok -> {:stop, :normal, %{state | disk: nil}}
        error -> {:stop, {:sleep_failed, error}, state}
      end
    end
  end

  defp keep(state),
    do: Disk.keep(state.disk, "session", Map.take(state, [:cwd, :env, :browser, :lines]))

  defp sleep_now(state) do
    with :ok <- Db.checkpoint_and_close(state.disk),
         {:ok, body} <- File.read(state.path),
         :ok <- Objects.put(Objects.computer_key(state.id), body) do
      for suffix <- ["", "-wal", "-shm"], do: File.rm(state.path <> suffix)
      :ok
    end
  end

  defp now, do: System.monotonic_time(:millisecond)
end

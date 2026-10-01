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

  Asleep, the computer is its log in the object store: the segments Litestream
  streamed while it was awake (`Moss.Litestream`, `Moss.Objects.Shipper`), or,
  kept whole, its file (`computers/<id>.sqlite`); `run` wakes it. It sleeps by itself after `idle_ms` with nothing to do. Every
  command is broadcast on `computer:<id>` for a person watching
  (`ComputerLive`).

  Everything it does is an event on its log (`Moss.Log`, PROJECT.md §15): its
  disk's changes, each run (`Run Command`), each request to its app (`Serve
  Request`, by the person using it), each letter it sends (`Send Mail`, after
  the run that sent it) and each one it is delivered (`Receive Mail`, as it
  arrives or, asleep, on its next wake).
  """
  use GenServer
  require Logger
  alias Moss.{Litestream, Log, Mail, Objects}
  alias Moss.Objects.Shipper
  alias Moss.Computer.{Browser, Disk, Script, Shell}

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

  @doc """
  Posts a letter from computer `id` (`Moss.Mail.post/4`) and tells the computer,
  which logs it when the run that sent it is over. Called inside a run, so the
  computer's own process is busy: the post never calls back into it.
  """
  def mail(id, to, subject, body) do
    result = Mail.post(id, to, subject, body)
    if pid = whereis(id), do: send(pid, {:mailed, to, subject, body, result})
    result
  end

  @doc "One request to the computer's app (`Moss.Computer.Script.serve/2`): `{status, headers, body, err}`."
  def serve(id, req), do: GenServer.call(wake!(id), {:serve, req}, :infinity)
  def sleep(id), do: if(pid = whereis(id), do: GenServer.call(pid, :sleep), else: :ok)

  def whereis(id) do
    case Registry.lookup(@registry, id) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc "Whether `id` can name a computer: lower-case letters, digits and dashes, at most 64, a letter or digit first."
  def id?(id), do: is_binary(id) and Regex.match?(~r/\A[a-z0-9][a-z0-9-]{0,63}\z/, id)

  def wake!(id, opts \\ []) do
    # an id becomes a file name and an object key, so it is checked before either is made
    unless id?(id), do: raise(ArgumentError, "not a computer id: #{inspect(id)}")

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
         {:ok, disk} <- Disk.open(path, id) do
      :ok = Disk.mkdir_p(disk, "/home")
      :ok = Disk.mkdir_p(disk, "/tmp")
      disk = %{disk | actor: "agent"}
      Phoenix.PubSub.subscribe(Moss.PubSub, "mail:" <> id)
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
       }, {:continue, :mail}}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  # A computer whose file is not on this node wakes from its log's segments when Litestream streams it, else
  # (and when it has none, a computer from before) from its whole file.
  defp pull(id, path) do
    cond do
      File.exists?(path) -> :ok
      Litestream.mode() == :litestream -> restore(id, path)
      true -> pull_whole(id, path)
    end
  end

  defp restore(id, path) do
    case Shipper.restore(id, path) do
      :ok -> :ok
      :none -> pull_whole(id, path)
      {:error, reason} -> {:error, {:restore, reason}}
    end
  end

  defp pull_whole(id, path) do
    case Objects.get(Objects.computer_key(id)) do
      {:ok, body} -> File.write(path, body)
      :not_found -> :ok
      {:error, reason} -> {:error, {:pull, reason}}
    end
  end

  @impl true
  def handle_call({:run, line}, _from, state) do
    started = System.monotonic_time(:microsecond)
    cwd = state.cwd
    {r, state} = Shell.run(line, state)
    ms = (System.monotonic_time(:microsecond) - started) / 1000
    log_mailed(state, "agent")
    log(state, "Run Command", [line, cwd, to_string(r.code), ms(ms), r.out, r.err], "agent")
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

    Disk.rest(state.disk)
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

  def handle_call({:serve, req}, _from, state) do
    started = System.monotonic_time(:microsecond)

    {status, _, body, _} =
      answer = Script.serve(req, %{state | disk: %{state.disk | actor: "user"}})

    ms = (System.monotonic_time(:microsecond) - started) / 1000
    log_mailed(state, "user")
    form = Plug.Conn.Query.encode(Enum.concat(req["query"] || %{}, req["form"] || %{}))
    method = to_string(req["method"] || "GET")
    path = to_string(req["path"] || "/")
    log(state, "Serve Request", [method, path, to_string(status), ms(ms), form, body], "user")

    Disk.rest(state.disk)
    {:reply, answer, %{state | touched: now()}, :hibernate}
  end

  def handle_call(:view, _from, state) do
    {:reply,
     %{
       id: state.id,
       cwd: state.cwd,
       lines: Enum.reverse(state.lines),
       browser: state.browser,
       files: Disk.list(state.disk, state.cwd),
       app?: match?({:ok, %{dir: false}}, Disk.stat(state.disk, "/home/app.lua"))
     }, state}
  end

  def handle_call(:sleep, _from, state) do
    case sleep_now(state) do
      :ok -> {:stop, :normal, :ok, %{state | disk: nil}}
      # its disk is closed and its files are still on the node: the next wake opens them
      error -> {:stop, :normal, error, %{state | disk: nil}}
    end
  end

  @impl true
  def handle_continue(:mail, state) do
    state = received(state)
    Disk.rest(state.disk)
    {:noreply, state, :hibernate}
  end

  @impl true
  def handle_info({:mail, _letter}, state) do
    state = received(state)
    Disk.rest(state.disk)
    {:noreply, state, :hibernate}
  end

  def handle_info({:mailed, _, _, _, _} = m, state) do
    log_mail(state, m, "agent")
    {:noreply, state}
  end

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

  # -- the log ------------------------------------------------------------------------------------

  # an event on the computer's log; one that cannot be written (a full disk) is told, never fatal to the run
  defp log(state, keyword, args, actor) do
    with {:error, why} <- Log.append(state.disk.conn, state.id, keyword, args, actor) do
      Logger.warning("computer #{state.id}: #{keyword} not logged: #{why}")
    end
  end

  defp ms(ms), do: :erlang.float_to_binary(ms / 1, decimals: 3)

  # the letters a run sent (Computer.mail/4), each a Send Mail with what the post did with it
  defp log_mailed(state, actor) do
    receive do
      {:mailed, _, _, _, _} = m ->
        log_mail(state, m, actor)
        log_mailed(state, actor)
    after
      0 -> :ok
    end
  end

  defp log_mail(state, {:mailed, to, subject, body, result}, actor) do
    {outcome, letter} =
      case result do
        {:refused, why} -> {"refused: #{why}", ""}
        {outcome, id} -> {to_string(outcome), to_string(id)}
      end

    log(state, "Send Mail", [to, subject, body, outcome, letter], actor)
  end

  # Letters delivered to this computer that its log does not yet hold, each a Receive Mail: the log's own
  # events name the ones it holds, and the post gives the rest.
  defp received(state) do
    {:ok, held} =
      Moss.Db.exec(
        state.disk.conn,
        "select a.value from events e join args a on a.seq = e.seq and a.pos = 4 " <>
          "where e.keyword = 'Receive Mail'",
        []
      )

    except = for %{"value" => v} <- held, {n, ""} <- [Integer.parse(v)], do: n

    for l <- Mail.inbox_except(state.id, except) do
      log(
        state,
        "Receive Mail",
        [l["sender"], l["subject"], l["body"], to_string(l["id"])],
        "host"
      )
    end

    state
  end

  # Asleep, a computer is its log in the store: streamed, Litestream's last sync and the shipper's last segments,
  # and only then its files on this node go; kept whole, its whole file. Its files stay on the node until the
  # store holds it, so a failed sleep loses nothing and the next wake opens them.
  defp sleep_now(state) do
    if Litestream.mode() == :litestream, do: sleep_streamed(state), else: sleep_whole(state)
  end

  defp sleep_streamed(state) do
    with :ok <- Disk.close(state.disk),
         {:ok, _txid} <- Litestream.stop(state.path),
         {:ok, _} <- Shipper.retire(state.id, fn -> remove(state) end) do
      :ok
    end
  end

  defp remove(state) do
    for suffix <- ["", "-wal", "-shm"], do: File.rm(state.path <> suffix)
    File.rm_rf(Litestream.meta_dir(state.id))
    File.rm_rf(Litestream.replica_dir(state.id))
  end

  defp sleep_whole(state) do
    with :ok <- Disk.close(state.disk),
         {:ok, body} <- File.read(state.path),
         :ok <- Objects.put(Objects.computer_key(state.id), body) do
      for suffix <- ["", "-wal", "-shm"], do: File.rm(state.path <> suffix)
      :ok
    end
  end

  defp now, do: System.monotonic_time(:millisecond)
end

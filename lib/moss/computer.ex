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

  Asleep, the computer is its whole file in the object store
  (`computers/<id>.sqlite`); awake, Litestream streams it on the node and the
  node keeps its recent work in packs (the host's, `Moss.Host`); `run` wakes it. It sleeps by itself after `idle_ms` with nothing to do. Every
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
  alias Moss.{Host, Log}
  alias Moss.Computer.{Browser, Disk, Script, Session, Shell}

  @registry Moss.Computer.Registry
  @lines 200

  def run(id, line), do: run(id, line, nil)

  # `under`: the task the run's events go under (an agent's step address), the computer's own when nil
  defp run(id, line, under), do: GenServer.call(wake!(id), {:run, line, under}, :infinity)

  @doc """
  The core's exec port (`ports.box`'s contract) on this computer: `files` are
  written first (path => content, relative to `cwd`), then `cmd` runs in `cwd`. `task`, when given, is what the
  writes and the run are logged under (an agent's step address), so the log reads a step's work as one.
  """
  def exec(id, %{} = req) do
    cwd = req["cwd"] || "/home"
    under = req["task"]

    with :ok <- GenServer.call(wake!(id), {:files, cwd, req["files"] || %{}, under}) do
      r = run(id, "cd '#{String.replace(cwd, "'", "")}' && " <> (req["cmd"] || "true"), under)
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
  Posts a letter from computer `id` (`Moss.Host.post/4`) and tells the computer,
  which logs it when the run that sent it is over. Called inside a run, so the
  computer's own process is busy: the post never calls back into it.
  """
  def mail(id, to, subject, body) do
    result = Host.post(id, to, subject, body)
    if pid = whereis(id), do: send(pid, {:mailed, to, subject, body, result})
    result
  end

  @doc "One request to the computer's app (`Moss.Computer.Script.serve/2`): `{status, headers, body, err}`."
  def serve(id, req), do: GenServer.call(wake!(id), {:serve, req}, :infinity)

  @doc "The person's yes to one request a tool asks for (`Moss.Computer.Person`): `:ok` or `{:error, why}`."
  def grant(id, tool, reach, value),
    do: GenServer.call(wake!(id), {:person, :grant, [tool, reach, value]})

  def revoke(id, tool, reach, value),
    do: GenServer.call(wake!(id), {:person, :revoke, [tool, reach, value]})

  @doc "The person agrees to a feature as it stands (`Moss.Computer.Person.agree/2`)."
  def agree(id, path), do: GenServer.call(wake!(id), {:person, :agree, [path]})

  @doc "The person's answer to a tool marked ASK, or to a publish; a yes runs it."
  def answer(id, line, yes?),
    do: GenServer.call(wake!(id), {:person, :answer, [line, yes?]}, :infinity)

  @doc "For the computer's own agent (`Moss.Computer.Agent`): its facts, or its log read or written, in here."
  def agent(id, fun, args) when fun in [:facts, :events, :append],
    do: GenServer.call(wake!(id), {:agent, fun, args}, :infinity)

  def sleep(id), do: if(pid = whereis(id), do: GenServer.call(pid, :sleep, :infinity), else: :ok)

  @doc "Computer `id`'s snapshot now, awake (`Moss.Host.cut/1`); one asleep is whole already."
  def snapshot(id),
    do: if(pid = whereis(id), do: GenServer.call(pid, :snapshot, :infinity), else: :ok)

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

    with :ok <- Host.pull(id, path),
         {:ok, disk} <- Disk.open(path, id) do
      :ok = Disk.mkdir_p(disk, "/home")
      :ok = Disk.mkdir_p(disk, "/tmp")
      Host.computer(id)
      :ok = Moss.Computer.Procedures.ensure(disk)
      disk = %{disk | actor: "agent"}
      Phoenix.PubSub.subscribe(Moss.PubSub, "mail:" <> id)
      idle = opts[:idle_ms] || Application.get_env(:moss, :idle_ms, 300_000)
      Process.send_after(self(), :idle, idle)
      if Host.streamed?(), do: snapshot_later()
      kept = Session.kept(disk, %{})

      {:ok,
       %{
         id: id,
         path: path,
         disk: disk,
         cwd: Map.get(kept, :cwd, "/home"),
         env: Map.get(kept, :env, %{"HOME" => "/home", "USER" => "agent", "PATH" => "/bin"}),
         last_code: 0,
         browser: Browser.restore(Map.get(kept, :browser)),
         lines: Map.get(kept, :lines, []),
         idle: idle,
         touched: now()
       }, {:continue, :mail}}
    else
      {:error, reason} -> {:stop, reason}
    end
  end

  @impl true
  # the calls without `under`, as hosts and their tests sent them before it
  def handle_call({:run, line}, from, state), do: handle_call({:run, line, nil}, from, state)
  def handle_call({:files, cwd, files}, from, state), do: handle_call({:files, cwd, files, nil}, from, state)

  def handle_call({:run, line, under}, _from, state) do
    started = System.monotonic_time(:microsecond)
    cwd = state.cwd
    {r, state} = Shell.run(line, put_in(state.disk.under, under))
    state = put_in(state.disk.under, nil)
    ms = (System.monotonic_time(:microsecond) - started) / 1000
    log_mailed(state, "agent")
    log(state, "Run Command", [line, cwd, to_string(r.code), ms(ms), r.out, r.err], "agent", under)
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

  def handle_call({:files, cwd, files, under}, _from, state) do
    disk = %{state.disk | under: under}
    :ok = Disk.mkdir_p(disk, Disk.norm(cwd))

    result =
      Enum.reduce_while(files, :ok, fn {path, body}, :ok ->
        case Disk.write(disk, Disk.norm(path, Disk.norm(cwd)), body) do
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
    # what the page showed nothing for is the agent's to read, never the person's
    {s, headers, b, e} = answer
    {:reply, {s, Map.delete(headers, "x-moss-nil"), b, e}, %{state | touched: now()}, :hibernate}
  end

  def handle_call({:person, what, args}, _from, state) do
    reply = apply(Moss.Computer.Person, what, [state | args])
    Disk.rest(state.disk)
    {:reply, reply, %{state | touched: now()}}
  end

  def handle_call({:agent, fun, args}, _from, state) do
    reply = apply(Moss.Computer.Agent, fun, [state | args])
    {:reply, reply, %{state | touched: now()}}
  end

  def handle_call(:view, _from, state) do
    {:reply,
     %{
       id: state.id,
       cwd: state.cwd,
       lines: Enum.reverse(state.lines),
       browser: state.browser,
       files: Disk.list(state.disk, state.cwd),
       app?: match?({:ok, %{dir: false}}, Disk.stat(state.disk, "/home/ui/index.lui"))
     }, state}
  end

  def handle_call(:snapshot, _from, state) do
    case Host.cut(state) do
      {:stop, why, state} -> {:stop, why, {:error, why}, state}
      {result, state} -> {:reply, result, state}
    end
  end

  def handle_call(:sleep, _from, state) do
    case Host.sleep(state) do
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

  def handle_info(:snapshot, state) do
    case Host.cut(state) do
      {:stop, why, state} ->
        {:stop, why, state}

      {result, state} ->
        with {:error, why} <- result,
             do:
               Logger.warning(
                 "computer #{state.id}: not snapshotted, its packs kept: #{inspect(why)}"
               )

        snapshot_later()
        {:noreply, state, :hibernate}
    end
  end

  def handle_info(:idle, state) do
    left = state.touched + state.idle - now()

    if left > 0 do
      Process.send_after(self(), :idle, left)
      {:noreply, state, :hibernate}
    else
      case Host.sleep(state) do
        :ok -> {:stop, :normal, %{state | disk: nil}}
        error -> {:stop, {:sleep_failed, error}, state}
      end
    end
  end

  # the session beside the files; one not kept (a file busy too long) is told, and the next command keeps it
  defp keep(state) do
    with {:error, why} <-
           Session.keep(
             state.disk,
             state
             |> Map.take([:cwd, :env, :lines])
             |> Map.put(:browser, Browser.kept(state.browser))
           ),
         do: Logger.warning("computer #{state.id}: session not kept: #{why}")
  end

  # -- the log ------------------------------------------------------------------------------------

  # an event on the computer's log; one that cannot be written (a full disk) is told, never fatal to the run
  defp log(state, keyword, args, actor, under \\ nil) do
    with {:error, why} <- Log.append(state.disk.conn, under || state.id, keyword, args, actor) do
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

    for l <- Host.inbox_except(state.id, except) do
      log(
        state,
        "Receive Mail",
        [l["sender"], l["subject"], l["body"], to_string(l["id"])],
        "host"
      )
    end

    state
  end

  # A computer awake longer than snapshot_ms (4 hours, config.exs says why) is snapshotted where it is,
  # so its old packs can go (Moss.Host.cut/1).
  defp snapshot_later,
    do: Process.send_after(self(), :snapshot, Application.fetch_env!(:moss, :snapshot_ms))

  defp now, do: System.monotonic_time(:millisecond)
end

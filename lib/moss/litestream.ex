defmodule Moss.Litestream do
  @moduledoc """
  The node's Litestream (Arock PROJECT.md §15.4): a pinned upstream binary
  beside Moss, run by the host and never reachable by an agent. It streams
  every awake computer's file (`work_dir/computers/<id>.sqlite`, its alog log)
  to a file replica on the node, `work_dir/replica/<id>.sqlite/ltx/<level>/`,
  as immutable segments; `Moss.Objects.Shipper` ships those through Arock's
  service with the node's own token. Nothing here holds a key: the node's only
  credential is that token.

  Config `replication:` is `:litestream`, `:whole` (a sleeping computer is its
  whole file, uploaded at sleep) or `:auto` (Litestream when its binary is
  found). The binary is config `litestream_bin`, else MOSS_LITESTREAM, else
  `litestream` on the PATH; 0.5.4 or later, for its directory watcher and its
  control socket.

  This process writes the config (`litestream_config/1`) into `work_dir` and
  runs `litestream replicate` under it; Litestream's control socket is
  `work_dir/litestream.sock`, given relative to `work_dir` because a Unix
  socket's path is at most 104 bytes. `stop/1` and `restore/2` are its
  commands, run from the caller.
  """
  use GenServer
  require Logger

  @socket "litestream.sock"

  @doc "`:litestream` or `:whole`: how this node keeps a sleeping computer."
  def mode do
    case Application.get_env(:moss, :replication, :auto) do
      :litestream -> :litestream
      :whole -> :whole
      :auto -> if bin(), do: :litestream, else: :whole
    end
  end

  def bin do
    Application.get_env(:moss, :litestream_bin) ||
      present(System.get_env("MOSS_LITESTREAM")) ||
      System.find_executable("litestream")
  end

  defp present(s) when is_binary(s) and s != "", do: s
  defp present(_), do: nil

  defp work_dir, do: Application.fetch_env!(:moss, :work_dir)

  @doc "Where computers' files live while they are awake."
  def computers_dir, do: Path.join(work_dir(), "computers")

  @doc "The node's file replica: one folder per computer, `<id>.sqlite/ltx/<level>/<min>-<max>.ltx`."
  def replica_root, do: Path.join(work_dir(), "replica")
  def replica_dir(id), do: Path.join(replica_root(), id <> ".sqlite")

  @doc "Litestream's own state beside a computer's file, rebuilt from the replica when it is gone."
  def meta_dir(id), do: Path.join(computers_dir(), "." <> id <> ".sqlite-litestream")

  @doc """
  The config: the directory watcher over the computers' files, each streamed
  to the file replica every second, and the control socket. alog's
  `litestream.yml` is this file with `${MOSS_WORK_DIR}` for the paths.
  """
  def litestream_config(dir) do
    """
    # Written by Moss.Litestream; alog's litestream.yml describes it. No key: the replica is a folder on this node.
    socket:
      enabled: true
      path: #{@socket}
    dbs:
      - dir: #{Path.join(dir, "computers")}
        pattern: "*.sqlite"
        recursive: false
        watch: true
        replica:
          type: file
          path: #{Path.join(dir, "replica")}
          sync-interval: #{Application.get_env(:moss, :litestream_sync, "1s")}
    """
  end

  @doc """
  Litestream's last sync of a computer's file, after the computer closed it:
  `sync -wait` until the replica holds the file's last transaction
  (`replicated_txid` is `txid`), then `stop`. A file Litestream has not yet
  seen (woken and slept within its watcher's delay) is waited for, up to
  `wait_ms`. `{:ok, txid}` once every write is in the replica.
  """
  def stop(path, wait_ms \\ 5_000) do
    deadline = System.monotonic_time(:millisecond) + wait_ms

    with {:ok, txid} <- synced(path, deadline),
         {_, 0} <- cmd(["stop", "-socket", @socket, "-timeout", "60", path]) do
      {:ok, txid}
    else
      {out, status} when is_integer(status) -> {:error, "litestream stop: " <> clip(out)}
      {:error, _} = e -> e
    end
  end

  defp synced(path, deadline) do
    case cmd(["sync", "-wait", "-timeout", "60", "-socket", @socket, path]) do
      {out, 0} ->
        case Jason.decode(json_part(out)) do
          {:ok, %{"txid" => t, "replicated_txid" => t}} when t > 0 -> {:ok, t}
          _ -> retry(path, deadline, out)
        end

      {out, _} ->
        if String.contains?(out, "database not found"),
          do: retry(path, deadline, out),
          else: {:error, "litestream sync: " <> clip(out)}
    end
  end

  defp retry(path, deadline, out) do
    if System.monotonic_time(:millisecond) < deadline do
      Process.sleep(50)
      synced(path, deadline)
    else
      {:error, "litestream sync: " <> clip(out)}
    end
  end

  # the JSON object Litestream prints, without any log line before it
  defp json_part(out) do
    case :binary.match(out, "{") do
      {at, _} -> binary_part(out, at, byte_size(out) - at)
      :nomatch -> out
    end
  end

  defp clip(out), do: String.slice(out, 0, 300)

  @doc "Rebuilds a computer's file at `out` from the file replica at `replica`."
  def restore(replica, out) do
    case cmd(["restore", "-o", out, "file://" <> replica]) do
      {_, 0} -> :ok
      {out, _} -> {:error, "litestream restore: " <> clip(out)}
    end
  end

  defp cmd(args) do
    case bin() do
      nil -> {"no litestream binary", 127}
      bin -> System.cmd(bin, args, cd: work_dir(), stderr_to_stdout: true)
    end
  end

  # -- the replicating process --------------------------------------------------------------------

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)
    dir = work_dir()
    File.mkdir_p!(Path.join(dir, "computers"))
    File.mkdir_p!(Path.join(dir, "replica"))
    config = Path.join(dir, "litestream.yml")
    File.write!(config, litestream_config(dir))
    kill_stale(dir)
    File.rm(Path.join(dir, @socket))

    port =
      Port.open({:spawn_executable, bin() || raise("no litestream binary")}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        {:line, 4096},
        {:cd, dir},
        {:args, ["replicate", "-no-expand-env", "-config", config]}
      ])

    {:os_pid, pid} = Port.info(port, :os_pid)
    File.write!(Path.join(dir, "litestream.pid"), to_string(pid))
    wait_for_socket(dir, 100)
    {:ok, %{port: port, pid: pid, dir: dir}}
  end

  # the control socket is up once Litestream is ready to be asked
  defp wait_for_socket(_dir, 0), do: :ok

  defp wait_for_socket(dir, n) do
    unless File.exists?(Path.join(dir, @socket)) do
      Process.sleep(20)
      wait_for_socket(dir, n - 1)
    end
  end

  # A Litestream this node started before and did not stop (the BEAM killed outright) is stopped first.
  defp kill_stale(dir) do
    with {:ok, text} <- File.read(Path.join(dir, "litestream.pid")),
         {pid, ""} <- Integer.parse(String.trim(text)),
         {comm, 0} <- System.cmd("ps", ["-p", to_string(pid), "-o", "comm="]),
         true <- String.contains?(comm, "litestream") do
      System.cmd("kill", [to_string(pid)])
      Process.sleep(200)
    end

    :ok
  end

  @impl true
  def handle_info({port, {:data, {_, line}}}, %{port: port} = state) do
    if String.contains?(line, "level=ERROR") or String.contains?(line, "level=WARN"),
      do: Logger.warning("litestream: " <> line)

    {:noreply, state}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state),
    do: {:stop, {:litestream_exited, status}, state}

  def handle_info(_, state), do: {:noreply, state}

  # SIGTERM: Litestream syncs what it holds and exits
  @impl true
  def terminate(_reason, %{pid: pid, dir: dir}) do
    System.cmd("kill", [to_string(pid)])
    File.rm(Path.join(dir, "litestream.pid"))
    :ok
  end
end

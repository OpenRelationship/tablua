defmodule Moss.Objects.Shipper do
  @moduledoc """
  Ships each awake computer's log, the segments Litestream writes to the
  node's file replica (`Moss.Litestream`), through the object store
  (`Moss.Objects.log_*`: Arock's service with the node's own token, or the
  local directory), and deletes the ones Litestream compacted away, so the
  store holds what the replica holds (Arock PROJECT.md §14.7 goal 6, §15).

  Every `ship_ms` (1 s) it ships each computer in the replica. What the store
  holds is listed once per computer and then remembered, so a restarted node
  starts from the store's own list against the files on disk: shipping is
  idempotent, a segment that went up is never sent again, and one that failed
  is sent on the next round. New segments go up before compacted ones are
  deleted, so the store can always restore the file; a computer with no
  segment on the node deletes nothing.

  `retire/2` is a computer's sleep: ship its last segments and, once the store
  holds them all, run the caller's cleanup. `restore/2` is its wake: the
  store's segments into the replica, and Litestream's restore from them. Each
  holds the computer's lock, which the rounds skip rather than wait for.
  """
  use GenServer
  require Logger
  alias Moss.{Litestream, Objects}

  @table __MODULE__

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc """
  Ships computer `id` now: `{:ok, %{put: n, deleted: n}}` or `{:error, why}`
  (nothing deleted when a put failed).
  """
  def ship(id), do: locked(id, :infinity, fn -> ship_now(id) end)

  @doc """
  A computer's sleep, after Litestream's last sync of its file: ships the
  rest, then runs `cleanup` (which removes the computer's files on the node)
  while still holding the computer, so no round sees it half gone. A computer
  with no segment on the node is refused: its file was never streamed.
  """
  def retire(id, cleanup) do
    locked(id, :infinity, fn ->
      with false <- local(id) == %{},
           {:ok, shipped} <- ship_now(id) do
        cleanup.()
        :ets.delete(@table, id)
        {:ok, shipped}
      else
        true -> {:error, "no segment of #{id} on this node: Litestream has not streamed it"}
        error -> error
      end
    end)
  end

  @doc """
  A computer's wake when its file is not on the node: its segments from the
  store into the replica (`Litestream.replica_dir/1`), then the file rebuilt
  from them at `path`. `:none` when the store holds no segment for it.
  """
  def restore(id, path) do
    locked(id, :infinity, fn ->
      with {:ok, remote} when remote != %{} <- Objects.log_list(id),
           {:ok, tmp} <- download(id, remote) do
        dir = Litestream.replica_dir(id)
        File.rm_rf!(dir)
        File.rm_rf!(Litestream.meta_dir(id))
        File.mkdir_p!(Path.dirname(dir))
        :ok = File.rename(tmp, dir)
        :ets.insert(@table, {id, remote})
        out = Path.join([Path.dirname(Litestream.replica_root()), "restore", id <> ".sqlite"])
        File.mkdir_p!(Path.dirname(out))
        for s <- ["", "-wal", "-shm"], do: File.rm(out <> s)

        with :ok <- Litestream.restore(dir, out), do: File.rename(out, path)
      else
        {:ok, %{}} -> :none
        {:error, _} = e -> e
      end
    end)
  end

  # every segment at once (a wake waits on it), into a folder the replica's name is given only when all are in
  defp download(id, remote) do
    tmp = Path.join(Litestream.replica_root(), ".#{id}.#{System.unique_integer([:positive])}")

    failed =
      remote
      |> Map.keys()
      |> Task.async_stream(
        fn name ->
          case Objects.log_get(id, name) do
            {:ok, body} ->
              file = Path.join([tmp, "ltx", name])
              File.mkdir_p!(Path.dirname(file))
              File.write!(file, body)

            other ->
              {:restore, name, other}
          end
        end,
        max_concurrency: Application.get_env(:moss, :restore_concurrency, 16),
        timeout: 120_000
      )
      |> Enum.find(fn r -> r != {:ok, :ok} end)

    if failed, do: tap({:error, failed}, fn _ -> File.rm_rf(tmp) end), else: {:ok, tmp}
  end

  # -- one computer --------------------------------------------------------------------------------

  defp locked(id, retries, fun) do
    case :global.trans({{__MODULE__, id}, self()}, fun, [node()], retries) do
      :aborted -> :busy
      result -> result
    end
  end

  @doc "The segments of computer `id` in the node's replica, name => size."
  def local(id) do
    dir = Path.join(Litestream.replica_dir(id), "ltx")

    for f <- Path.wildcard(Path.join(dir, "*/*.ltx")),
        name = Path.relative_to(f, dir),
        Objects.segment?(name),
        {:ok, %{size: size}} <- [File.stat(f)],
        into: %{},
        do: {name, size}
  end

  defp remote(id) do
    case :ets.lookup(@table, id) do
      [{^id, held}] -> {:ok, held}
      [] -> Objects.log_list(id)
    end
  end

  defp ship_now(id) do
    local = local(id)

    with false <- local == %{},
         {:ok, held} <- remote(id),
         {:ok, held, put} <- put_new(id, local, held),
         {:ok, held, deleted} <- delete_gone(id, local, held) do
      :ets.insert(@table, {id, held})
      {:ok, %{put: put, deleted: deleted}}
    else
      true -> {:ok, %{put: 0, deleted: 0}}
      {:error, held, why} -> tap({:error, why}, fn _ -> :ets.insert(@table, {id, held}) end)
      {:error, _} = e -> e
    end
  end

  # oldest first, so the store's segments are a prefix of the replica's should a put fail
  defp put_new(id, local, held) do
    local
    |> Enum.reject(fn {name, size} -> held[name] == size end)
    |> Enum.sort_by(fn {name, _} -> {Path.basename(name), name} end)
    |> Enum.reduce_while({:ok, held, 0}, fn {name, size}, {:ok, held, n} ->
      file = Path.join([Litestream.replica_dir(id), "ltx", name])

      with {:ok, body} <- File.read(file),
           :ok <- Objects.log_put(id, name, body) do
        {:cont, {:ok, Map.put(held, name, size), n + 1}}
      else
        # compacted away between the listing and the read: the next round deletes it from the store
        {:error, :enoent} -> {:cont, {:ok, held, n}}
        {:error, why} -> {:halt, {:error, held, why}}
      end
    end)
  end

  defp delete_gone(id, local, held) do
    held
    |> Map.keys()
    |> Enum.reject(&Map.has_key?(local, &1))
    |> Enum.reduce_while({:ok, held, 0}, fn name, {:ok, held, n} ->
      case Objects.log_delete(id, name) do
        :ok -> {:cont, {:ok, Map.delete(held, name), n + 1}}
        {:error, why} -> {:halt, {:error, held, why}}
      end
    end)
  end

  # -- the rounds ----------------------------------------------------------------------------------

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set])
    send(self(), :round)
    {:ok, %{}}
  end

  @impl true
  def handle_info(:round, state) do
    ids =
      for d <- Path.wildcard(Path.join(Litestream.replica_root(), "*.sqlite")),
          id = Path.basename(d, ".sqlite"),
          Moss.Computer.id?(id),
          do: id

    ids
    |> Task.async_stream(fn id -> {id, locked(id, 0, fn -> ship_now(id) end)} end,
      max_concurrency: Application.get_env(:moss, :ship_concurrency, 8),
      timeout: :infinity
    )
    |> Enum.each(fn
      {:ok, {id, {:error, why}}} -> Logger.warning("log of #{id} not shipped: #{inspect(why)}")
      _ -> :ok
    end)

    Process.send_after(self(), :round, Application.get_env(:moss, :ship_ms) || 1_000)
    {:noreply, state}
  end
end

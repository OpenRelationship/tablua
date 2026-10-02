defmodule Moss.Objects.Snapshot do
  @moduledoc """
  A streamed computer's sleep and wake (Arock PROJECT.md §15 item 4). Asleep,
  a computer is its whole file in the store (`computers/<id>.sqlite`): one
  write per sleep, one read per wake. Awake, Litestream streams it to the
  node's replica and `Moss.Objects.Packer` keeps its recent work in packs.

  Each wake from the store starts a new chain of segments, numbered by the
  file's `user_version` (`gen`, stamped at the wake, carried by the snapshot),
  so the packs can tell one wake's segments from another's and a snapshot
  says which chain it ended. A computer that slept before packs has no
  number (0) and wakes from its old log (`Moss.Objects.Legacy`) when it has one.

  Both hold the computer's lock (`Moss.Objects.Lock`), so the packer never
  reads a chain half made or half removed.
  """
  alias Moss.{Litestream, Objects}
  alias Moss.Objects.{Ledger, Legacy, Lock}
  alias Moss.Computer.Disk

  @doc "The chain a SQLite file's bytes belong to, its `user_version`: 0 for anything else."
  def gen_of(<<"SQLite format 3", 0, _::binary-size(44), gen::32-big, _::binary>>), do: gen
  def gen_of(_), do: 0

  @doc "Where a sleeping computer's snapshot is written before it goes up."
  def tmp_path(id), do: Path.join([Litestream.replica_root(), ".snap", id <> ".sqlite"])

  @doc """
  A computer's wake when its file is not on the node: its snapshot (or its log
  from before packs) at `path`, stamped as the next chain. A computer whose
  file is on the node (a failed sleep, a BEAM that crashed) carries on its chain.
  """
  def wake(id, path) do
    Lock.locked(id, :infinity, fn ->
      if File.exists?(path), do: carry_on(id, path), else: fetch(id, path)
    end)
  end

  defp carry_on(id, path) do
    unless Ledger.gen(id) do
      gen =
        with {:ok, head} <- File.open(path, [:read, :binary], &IO.binread(&1, 100)),
             do: gen_of(head)

      Ledger.put_gen(id, max(gen, 1), %{})
    end

    :ok
  end

  defp fetch(id, path) do
    tmp = path <> ".waking"
    for s <- ["", "-wal", "-shm"], do: File.rm(tmp <> s)

    with {:ok, gen} <- base(id, tmp),
         :ok <- Disk.stamp(tmp, gen + 1) do
      File.rm_rf!(Litestream.replica_dir(id))
      File.rm_rf!(Litestream.meta_dir(id))
      Ledger.put_gen(id, gen + 1, %{})
      File.rename(tmp, path)
    end
  end

  # the file a wake starts from at `tmp`, and its chain: the snapshot, else the old log, else an old whole file
  defp base(id, tmp) do
    case Objects.get(Objects.computer_key(id)) do
      {:ok, body} ->
        if gen_of(body) > 0, do: write(tmp, body), else: old(id, tmp, body)

      :not_found ->
        old(id, tmp, nil)

      {:error, why} ->
        {:error, {:pull, why}}
    end
  end

  defp old(id, tmp, whole) do
    case Legacy.restore(id, tmp) do
      :ok -> {:ok, 0}
      :none when whole != nil -> write(tmp, whole)
      :none -> {:ok, 0}
      {:error, why} -> {:error, {:restore, why}}
    end
  end

  defp write(tmp, body) do
    File.mkdir_p!(Path.dirname(tmp))
    with :ok <- File.write(tmp, body), do: {:ok, gen_of(body)}
  end

  @doc """
  A computer's snapshot while it stays awake (`Moss.Computer`, every `snapshot_ms`): one awake for days never
  sleeps, so without it nothing would outgrow its packs. After `Disk.snapshot/2` wrote its whole file at `snap`
  and the disk closed, the snapshot goes up as the end of its chain, exactly as at a sleep, and becomes its file
  on the node as the next chain, as at a wake: Litestream finds a new file and streams it from a new replica, so
  the packs of the chain it ended are garbage and a lost disk rebuilds the new chain from its own packs.

  Litestream lets the file go before anything changes. A snapshot that fails to go up changes nothing: the file
  stays and Litestream carries on its chain. The computer opens its file again either way.
  """
  def cut(id, path, snap) do
    Lock.locked(id, :infinity, fn ->
      with {:ok, _txid} <- Litestream.stop(path),
           {:ok, body} <- up(id, path, snap) do
        let_go(id, path, gen_of(body))
        Ledger.put_gen(id, gen_of(body) + 1, %{})
        File.rename(snap, path)
      end
    end)
  after
    File.rm(snap)
  end

  # the whole file in the store and its copy on the node stamped as the next chain; when either fails, Litestream
  # streams the file on as if nothing happened
  defp up(id, path, snap) do
    with {:ok, body} <- File.read(snap),
         :ok <- Disk.stamp(snap, gen_of(body) + 1),
         :ok <- Objects.put(Objects.computer_key(id), body) do
      {:ok, body}
    else
      e -> tap(e, fn _ -> Litestream.resume(path) end)
    end
  end

  # a chain ended by a snapshot in the store: its file and replica leave the node and the ledger says so
  defp let_go(id, path, gen) do
    for s <- ["", "-wal", "-shm"], do: File.rm(path <> s)
    File.rm_rf(Litestream.meta_dir(id))
    File.rm_rf(Litestream.replica_dir(id))
    Ledger.drop_gen(id)
    Ledger.put_slept(id, gen)
  end

  @doc """
  A computer's sleep, after `Disk.snapshot/2` wrote its whole file at `snap`
  and the disk closed: the snapshot goes up, Litestream lets the file go, and
  only then its files leave the node and the ledger says which chain the
  snapshot ended. A failed sleep leaves everything on the node, the chain
  carrying on at the next wake.
  """
  def sleep(id, path, snap) do
    Lock.locked(id, :infinity, fn ->
      with {:ok, body} <- File.read(snap),
           :ok <- Objects.put(Objects.computer_key(id), body),
           {:ok, _txid} <- Litestream.stop(path) do
        let_go(id, path, gen_of(body))
      end
    end)
  after
    File.rm(snap)
  end
end

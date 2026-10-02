defmodule Moss.Computer.Keeping do
  @moduledoc """
  Where a computer's file is while it is not open (Arock PROJECT.md §15 item 4): pulled from the store at a wake,
  sent up whole at a sleep, and sent up whole while awake every `snapshot_ms`, which ends its chain so its old
  packs can go (`Moss.Objects.Snapshot`). Streamed by Litestream on a node; kept whole (`Moss.Litestream.mode/0`)
  only as its file after a checkpoint.
  """
  alias Moss.{Litestream, Objects}
  alias Moss.Objects.Snapshot
  alias Moss.Computer.Disk

  @doc """
  A computer whose file is not on this node wakes from its snapshot (streamed: as the next chain of its segments,
  `Moss.Objects.Snapshot.wake/2`), else from its whole file.
  """
  def pull(id, path) do
    cond do
      Litestream.mode() == :litestream -> Snapshot.wake(id, path)
      File.exists?(path) -> :ok
      true -> pull_whole(id, path)
    end
  end

  defp pull_whole(id, path) do
    case Objects.get(Objects.computer_key(id)) do
      {:ok, body} -> File.write(path, body)
      :not_found -> :ok
      {:error, reason} -> {:error, {:pull, reason}}
    end
  end

  @doc """
  Asleep, a computer is its whole file in the store: streamed, written whole beside the open disk and sent up
  before Litestream lets it go; kept whole, its file after a checkpoint. Its files stay on the node until the
  store holds it, so a failed sleep loses nothing and the next wake opens them.
  """
  def sleep(state) do
    if Litestream.mode() == :litestream, do: sleep_streamed(state), else: sleep_whole(state)
  end

  defp sleep_streamed(state) do
    with {:ok, snap} <- snapshot(state), :ok <- Disk.close(state.disk) do
      Snapshot.sleep(state.id, state.path, snap)
    end
  end

  defp sleep_whole(state) do
    with :ok <- Disk.close(state.disk),
         {:ok, body} <- File.read(state.path),
         :ok <- Objects.put(Objects.computer_key(state.id), body) do
      for suffix <- ["", "-wal", "-shm"], do: File.rm(state.path <> suffix)
      :ok
    end
  end

  @doc """
  An awake computer's snapshot (`Moss.Objects.Snapshot.cut/3`), streamed only: `{result, state}`, its file closed
  for the cut and opened again whatever happened, or `{:stop, why, state}` when it will not open, its file still on
  the node for the next wake. Kept whole, a computer has no packs to outgrow.
  """
  def cut(state) do
    if Litestream.mode() == :litestream do
      with {:ok, snap} <- snapshot(state) do
        Disk.close(state.disk)
        result = Snapshot.cut(state.id, state.path, snap)

        case Disk.open(state.path, state.id) do
          {:ok, disk} -> {result, %{state | disk: %{disk | actor: state.disk.actor}}}
          {:error, why} -> {:stop, {:reopen_failed, why}, %{state | disk: nil}}
        end
      else
        e -> {e, state}
      end
    else
      {:ok, state}
    end
  end

  # the disk whole beside it, while it is open
  defp snapshot(state) do
    snap = Snapshot.tmp_path(state.id)
    File.mkdir_p!(Path.dirname(snap))
    with :ok <- Disk.snapshot(state.disk, snap), do: {:ok, snap}
  end
end

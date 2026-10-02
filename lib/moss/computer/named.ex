defmodule Moss.Computer.Named do
  @moduledoc """
  A computer's manifests on the node's names (`Moss.Names`, Arock's feature manifest): a manifest.org written,
  removed or moved re-registers what it names, as the disk changes. The person's own requests and a disk with no
  computer name nothing.
  """
  alias Moss.Computer.Disk

  def written(%{task: id} = disk, path, data) when is_binary(id) do
    if disk.actor != "user" and String.ends_with?(path, "/manifest.org") and Process.whereis(Moss.Names),
      do: Moss.Names.manifest(id, path, data)

    :ok
  end

  def written(_, _, _), do: :ok

  def removed(%{task: id}, path) when is_binary(id) do
    if Process.whereis(Moss.Names), do: Moss.Names.gone(id, path)
    :ok
  end

  def removed(_, _), do: :ok

  def moved(disk, from, to) do
    removed(disk, from)

    for p <- [to, to <> "/manifest.org"], String.ends_with?(p, "/manifest.org"), {:ok, data} <- [Disk.read(disk, p)],
        do: written(disk, p, data)

    :ok
  end
end

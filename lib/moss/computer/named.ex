defmodule Moss.Computer.Named do
  @moduledoc """
  A computer's manifests on the node's names (`Moss.Names`, Arock's feature manifest): a manifest.org an agent
  writes is checked first, as arock-log checks it (a bad line, or a GRANTED only the host writes, refuses the write);
  written, removed or moved, it re-registers what it names and its triggers, and a request it no longer makes
  takes its grant back. The person's own requests and a disk with no computer name nothing.
  """
  alias Moss.Computer.{Disk, Manifest}

  @doc "`:ok`, or why an agent's manifest is refused, by line."
  def check(disk, path, data) do
    with true <- disk.actor != "user" and Path.basename(path) == "manifest.org",
         [_ | _] = errs <- Manifest.check(data) do
      {:error, "manifest.org is refused:\n" <> Enum.join(errs, "\n")}
    else
      _ -> :ok
    end
  end

  def written(%{task: id} = disk, path, data) when is_binary(id) do
    if disk.actor != "user" and String.ends_with?(path, "/manifest.org") and
         Process.whereis(Moss.Names) do
      Moss.Names.manifest(id, path, data)
      Manifest.revoke_dropped(disk, id)
    end

    :ok
  end

  def written(_, _, _), do: :ok

  def removed(%{task: id} = disk, path) when is_binary(id) do
    if Process.whereis(Moss.Names) do
      Moss.Names.gone(id, path)
      Manifest.revoke_dropped(disk, id)
    end

    :ok
  end

  def removed(_, _), do: :ok

  def moved(disk, from, to) do
    removed(disk, from)

    for p <- [to, to <> "/manifest.org"],
        String.ends_with?(p, "/manifest.org"),
        {:ok, data} <- [Disk.read(disk, p)],
        do: written(disk, p, data)

    :ok
  end
end

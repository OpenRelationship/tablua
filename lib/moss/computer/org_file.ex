defmodule Moss.Computer.OrgFile do
  @moduledoc """
  Org files on the log (Arock's feature file-kinds): a write of `org/**.org` (the computer's, or an app's) is
  checked whole against the file's history by arock-log (`arock-log.org_log`: unique IDs, links that resolve, allowed
  states, `CLOSED` stamped by the host, append-only history, nothing that runs) and kept as events (Add Entry,
  Set State, ...). The file on the disk is what the log reads back, IDs and stamps included; a refused write
  keeps nothing and names each line.
  """
  alias Moss.Computer.Disk

  @doc "`{:ok, data}`: the text to keep at `path` (read back from the log for an org file), or `{:error, why}`."
  def kept(%{task: task} = disk, path, data) when is_binary(task) do
    if org?(path) do
      resolve = &resolve(disk, path, &1)

      case Moss.Lua.call("org", [path, data, disk.actor, task], [db: disk.conn, resolve: resolve]) do
        {:ok, [text | _]} when is_binary(text) -> {:ok, text}
        {:ok, [nil, lines]} -> {:error, refused(path, Moss.Lua.list(lines))}
        {:error, why} -> {:error, "#{rel(path)}: #{why}"}
      end
    else
      {:ok, data}
    end
  end

  def kept(_disk, _path, data), do: {:ok, data}

  @doc "Whether `path` is an org file kept on the log: under a scope's org/."
  def org?(path),
    do: String.ends_with?(path, ".org") and Regex.match?(~r"\A/home/(apps/[a-z0-9][a-z0-9-]*/)?org/", path)

  defp refused(path, lines), do: "#{rel(path)} is refused:\n" <> Enum.join(lines, "\n")

  defp rel("/home/" <> p), do: p

  # org: addresses on the node; file: a file of the scope the org file is in; anything else is not checked here
  defp resolve(disk, path, "file:" <> file) do
    scope = Regex.run(~r"\A/home(/apps/[a-z0-9][a-z0-9-]*)?", path) |> hd()

    case Disk.stat(disk, Disk.norm(file, scope)) do
      {:ok, _} -> true
      _ -> {false, "the link file:#{file} names no file on this computer"}
    end
  end

  defp resolve(_disk, _path, "org:" <> _ = address) do
    case Moss.Host.resolve(address) do
      {:ok, _} -> true
      {:error, why} -> {false, why}
    end
  end

  defp resolve(_disk, _path, _target), do: true
end

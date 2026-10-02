defmodule Moss.Computer.Procedures do
  @moduledoc """
  The agent's procedures (Arock's features file-kinds and refine): how it works, as org files in
  `/home/org/procedures/`, kept on the log like any org (`Moss.Computer.OrgFile`). A computer gets the node's own
  (`priv/procedures/*.org`) on its first wake, written by the host; from then on they are its own, read into the
  model's context with `help`, and changed only by a refinement the person agrees to (feature refine).
  """
  alias Moss.Computer.Disk

  @dir "/home/org/procedures"

  @doc "Writes the node's procedures onto a computer that has none: `:ok`, or the first write's error."
  def ensure(disk) do
    case Disk.stat(disk, @dir) do
      {:ok, _} ->
        :ok

      _ ->
        host = %{disk | actor: "host"}

        Enum.reduce_while(files(), :ok, fn {name, text}, :ok ->
          case Disk.write(host, "#{@dir}/#{name}", text) do
            :ok -> {:cont, :ok}
            error -> {:halt, error}
          end
        end)
    end
  end

  @doc "The node's procedures: `[{file name, text}]`."
  def files do
    for f <- Path.wildcard(Path.join(:code.priv_dir(:moss), "procedures/*.org")) |> Enum.sort(),
        do: {Path.basename(f), File.read!(f)}
  end
end

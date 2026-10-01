defmodule Moss.Computer.Usr do
  @moduledoc """
  What every computer shares under `/usr`, read-only: the headers, libraries
  and standard libraries the programs need (a C compiler's `/usr/include` and
  `/usr/lib`, Python's own library), one folder on the node (config
  `system_root:`, what `just build-script computer` writes). An agent's own
  files are its disk's; nothing under `/usr` is ever written.
  """

  def owns?(path), do: path == "/usr" or String.starts_with?(path, "/usr/")

  def stat(path) do
    case File.stat(real(path), time: :posix) do
      {:ok, %{type: :directory, mtime: m}} -> {:ok, %{dir: true, size: 0, mtime: m}}
      {:ok, %{type: :regular, size: s, mtime: m}} -> {:ok, %{dir: false, size: s, mtime: m}}
      _ when path == "/usr" -> {:ok, %{dir: true, size: 0, mtime: 0}}
      _ -> {:error, :enoent}
    end
  end

  def read(path) do
    case File.read(real(path)) do
      {:ok, data} -> {:ok, data}
      {:error, :eisdir} -> {:error, :eisdir}
      {:error, _} -> {:error, :enoent}
    end
  end

  def list(path) do
    case File.ls(real(path)) do
      {:ok, names} ->
        {:ok,
         for name <- Enum.sort(names), {:ok, s} = stat(Path.join(path, name)) do
           Map.put(s, :name, name)
         end}

      {:error, :enotdir} ->
        {:error, :enotdir}

      _ when path == "/usr" ->
        {:ok, []}

      _ ->
        {:error, :enoent}
    end
  end

  # `path` is already normalised (Disk.norm), so it never leaves the root
  defp real(path), do: Path.join(Application.fetch_env!(:moss, :system_root), path)
end

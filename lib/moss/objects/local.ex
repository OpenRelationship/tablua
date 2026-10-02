defmodule Moss.Objects.Local do
  @moduledoc "Objects as files under the configured `local_objects` directory."
  @behaviour Moss.Objects
  import Bitwise, only: [<<<: 2]

  defp path(key), do: Path.join(Application.fetch_env!(:moss, :local_objects), key)

  @impl true
  def get(key) do
    case File.read(path(key)) do
      {:ok, body} -> {:ok, body}
      {:error, :enoent} -> :not_found
      {:error, reason} -> {:error, reason}
    end
  end

  # Written beside and renamed, so a reader never sees half a file.
  @impl true
  def put(key, body) do
    dest = path(key)
    tmp = dest <> ".part"

    with :ok <- File.mkdir_p(Path.dirname(dest)),
         :ok <- File.write(tmp, body) do
      File.rename(tmp, dest)
    end
  end

  @impl true
  def delete(key) do
    case File.rm(path(key)) do
      {:error, :enoent} -> :ok
      other -> other
    end
  end

  # a computer's log from before packs, read only: its segments under logs/<id>/<level>/<file>
  defp log_dir(id), do: path("logs/#{id}")

  @impl true
  def log_list(id) do
    dir = log_dir(id)

    segments =
      for f <- Path.wildcard(Path.join(dir, "*/*.ltx")),
          name = Path.relative_to(f, dir),
          Moss.Objects.segment?(name),
          into: %{},
          do: {name, File.stat!(f).size}

    {:ok, segments}
  end

  @impl true
  def log_get(id, name),
    do: if(Moss.Objects.segment?(name), do: get("logs/#{id}/#{name}"), else: :not_found)

  # this node's packs, under packs/<node>/
  defp pack_dir, do: path("packs/#{Moss.Objects.node_name()}")

  @impl true
  def pack_list do
    packs =
      for f <- Path.wildcard(Path.join(pack_dir(), "*.pack")),
          Moss.Objects.Pack.name?(Path.basename(f)),
          into: %{},
          do: {Path.basename(f), File.stat!(f).size}

    {:ok, packs}
  end

  @impl true
  def pack_get(name, range) do
    cond do
      not Moss.Objects.Pack.name?(name) -> :not_found
      range == nil -> get("packs/#{Moss.Objects.node_name()}/#{name}")
      true -> read_range(Path.join(pack_dir(), name), range)
    end
  end

  defp read_range(file, {first, last}) do
    case File.open(file, [:read, :binary], fn f ->
           :file.pread(f, first, if(last, do: last - first + 1, else: 1 <<< 40))
         end) do
      {:ok, {:ok, bytes}} -> {:ok, bytes}
      {:ok, :eof} -> {:ok, ""}
      {:error, :enoent} -> :not_found
      {:error, why} -> {:error, why}
    end
  end

  @impl true
  def pack_put(name, body),
    do:
      if(Moss.Objects.Pack.name?(name),
        do: put("packs/#{Moss.Objects.node_name()}/#{name}", body),
        else: {:error, :bad_pack}
      )

  @impl true
  def pack_delete(name),
    do:
      if(Moss.Objects.Pack.name?(name),
        do: delete("packs/#{Moss.Objects.node_name()}/#{name}"),
        else: {:error, :bad_pack}
      )
end

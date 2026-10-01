defmodule Moss.Objects.Local do
  @moduledoc "Objects as files under the configured `local_objects` directory."
  @behaviour Moss.Objects

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

  # a computer's log: its segments under logs/<id>/<level>/<file>
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

  @impl true
  def log_put(id, name, body),
    do:
      if(Moss.Objects.segment?(name),
        do: put("logs/#{id}/#{name}", body),
        else: {:error, :bad_segment}
      )

  @impl true
  def log_delete(id, name),
    do:
      if(Moss.Objects.segment?(name),
        do: delete("logs/#{id}/#{name}"),
        else: {:error, :bad_segment}
      )
end

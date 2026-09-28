defmodule VolvoxServer.Objects.Local do
  @moduledoc "Objects as files under the configured `local_objects` directory."
  @behaviour VolvoxServer.Objects

  defp path(key), do: Path.join(Application.fetch_env!(:volvox_server, :local_objects), key)

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
end

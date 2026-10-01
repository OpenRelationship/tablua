defmodule VolvoxServer.Agents do
  @moduledoc """
  Agents by name. A task the host drives on its own (a scheduled job, a task
  resumed after a restart) names its agent in the run's log, so the node must
  find the source again from the name alone: config `agents:` maps a name to
  a Lua file, a function(host) as `VolvoxServer.Run` takes. Each is parsed
  once and kept in `:persistent_term`.
  """

  @doc "The parsed agent called `name`, or `{:error, message}`."
  def chunk(name) do
    case :persistent_term.get({__MODULE__, name}, nil) do
      nil -> load(name)
      chunk -> {:ok, chunk}
    end
  end

  defp load(name) do
    with {:ok, path} <- path(name),
         {:ok, source} <- File.read(path) do
      chunk = VolvoxServer.Lua.agent!(source)
      :persistent_term.put({__MODULE__, name}, chunk)
      {:ok, chunk}
    else
      :none -> {:error, "there is no agent #{inspect(name)}"}
      {:error, reason} -> {:error, "agent #{name}: #{inspect(reason)}"}
    end
  end

  defp path(name) do
    case Map.fetch(Application.get_env(:volvox_server, :agents, %{}), name) do
      {:ok, path} -> {:ok, path}
      :error -> :none
    end
  end
end

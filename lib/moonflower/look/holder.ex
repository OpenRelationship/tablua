defmodule Moonflower.Look.Holder do
  @moduledoc """
  What runs inside the look node: the module loaded once and kept, and each look run against it. Called over
  `:peer` by `Moonflower.Look.Node`; nothing here runs in the node that asked.
  """
  alias Moonflower.Look.{Module, Run}

  @key {__MODULE__, :module}

  @doc "Loads and keeps the module: `:ok` or `{:error, :hash}`."
  def load(path, sha384) do
    with {:ok, loaded} <- Module.load(path, sha384) do
      :persistent_term.put(@key, loaded)
      :ok
    end
  end

  @doc "One look against the kept module (`Moonflower.Look.Run.run/4`)."
  def look(input, fuel, timeout), do: Run.run(:persistent_term.get(@key), input, fuel, timeout)
end

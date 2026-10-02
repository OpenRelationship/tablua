defmodule Moonflower.Look.Node do
  @moduledoc """
  The look node: a BEAM node of its own (`:peer`, over its standard input and output, no distribution), so wasmex
  and the module never run in the node that asks, and a fault there stops nothing here. Started with the module's
  path and the SHA-384 it must have; a module that does not match is refused and the node does not start. When the
  look node dies, the next look starts another.
  """
  use GenServer

  @doc "Options: `:path`, `:sha384`, and `:name` (default `#{inspect(__MODULE__)}`; nil for none)."
  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, if(name, do: [name: name], else: []))
  end

  @doc "The peer to call, started again if it died: `{:ok, peer}` or `{:error, why}`."
  def peer(node \\ __MODULE__), do: GenServer.call(node, :peer, 30_000)

  @doc "Kills the look node, as a fault would."
  def kill(node \\ __MODULE__), do: GenServer.call(node, :kill)

  @impl true
  def init(opts) do
    state = %{path: Keyword.fetch!(opts, :path), sha384: Keyword.fetch!(opts, :sha384), peer: nil}

    case start(state) do
      {:ok, state} -> {:ok, state}
      {:error, why} -> {:stop, why}
    end
  end

  @impl true
  def handle_call(:peer, _from, state) do
    state = if state.peer && Process.alive?(state.peer), do: state, else: %{state | peer: nil}

    case if(state.peer, do: {:ok, state}, else: start(state)) do
      {:ok, state} -> {:reply, {:ok, state.peer}, state}
      {:error, why} -> {:reply, {:error, why}, state}
    end
  end

  def handle_call(:kill, _from, state) do
    if state.peer, do: Process.exit(state.peer, :kill)
    {:reply, :ok, %{state | peer: nil}}
  end

  @impl true
  def handle_info({:DOWN, _, :process, pid, _}, %{peer: pid} = state),
    do: {:noreply, %{state | peer: nil}}

  def handle_info(_, state), do: {:noreply, state}

  defp start(state) do
    paths = Enum.flat_map(:code.get_path(), &[~c"-pa", &1])
    {:ok, peer, _} = :peer.start(%{connection: :standard_io, args: paths})
    Process.monitor(peer)

    case :peer.call(peer, Moonflower.Look.Holder, :load, [state.path, state.sha384], 60_000) do
      :ok ->
        {:ok, %{state | peer: peer}}

      {:error, why} ->
        :peer.stop(peer)
        {:error, why}
    end
  end
end

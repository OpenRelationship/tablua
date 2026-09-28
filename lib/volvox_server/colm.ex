defmodule VolvoxServer.Colm do
  @moduledoc """
  The Colm suite under Wasmex: one process per suite module (`outline`,
  `python`, `robot`, `lua`, ...), started on first use, holding a compiled
  module and one live instance. `run(name, src)` is the suite's run(src)
  contract (`library/suite/init.lua`): write src through `vv_input`, call
  `vv_run`, read stdout and stderr through `vv_output`/`vv_output_len`.

  Instances are recycled the way `suite.runner` recycles them: a fresh one
  every #{200} runs (a long-lived instance slows down) and after a trap (a
  trapped instance is dead), which is reported as status -1.
  """
  use GenServer

  @every 200
  @timeout 60_000

  @doc "Runs the suite module `name` over `src`: `{stdout, status, stderr}`."
  def run(name, src) do
    GenServer.call(server(name), {:run, src}, :infinity)
  end

  defp server(name) do
    case Registry.lookup(VolvoxServer.Colm.Registry, name) do
      [{pid, _}] -> pid
      [] -> start(name)
    end
  end

  defp start(name) do
    spec = {__MODULE__, name}

    case DynamicSupervisor.start_child(VolvoxServer.Colm.Supervisor, spec) do
      {:ok, pid} -> pid
      {:error, {:already_started, pid}} -> pid
    end
  end

  def child_spec(name), do: %{id: {__MODULE__, name}, start: {__MODULE__, :start_link, [name]}}

  def start_link(name) do
    GenServer.start_link(__MODULE__, name,
      name: {:via, Registry, {VolvoxServer.Colm.Registry, name}}
    )
  end

  @impl true
  def init(name) do
    unless name =~ ~r/^[a-z0-9_]+$/,
      do: raise(ArgumentError, "bad suite module name #{inspect(name)}")

    path = Path.join(Application.fetch_env!(:volvox_server, :suite), name <> ".wasm")
    {:ok, engine} = Wasmex.Engine.new(%Wasmex.EngineConfig{})
    {:ok, store} = Wasmex.Store.new(nil, engine)
    {:ok, module} = Wasmex.Module.compile(store, File.read!(path))
    {:ok, %{engine: engine, module: module, instance: nil, runs: 0}}
  end

  @impl true
  def handle_call({:run, src}, _from, state) do
    state = %{state | runs: state.runs + 1}
    state = if rem(state.runs, @every) == 0, do: recycle(state), else: ensure(state)

    case transform(state.instance, src) do
      {:ok, result} -> {:reply, result, state}
      {:error, reason} -> {:reply, {"", -1, "trap: #{format(reason)}"}, recycle(state)}
    end
  end

  defp ensure(%{instance: nil} = state), do: recycle(state)
  defp ensure(state), do: state

  defp recycle(state) do
    if state.instance, do: GenServer.stop(state.instance.pid)
    {:ok, store} = Wasmex.Store.new(nil, state.engine)
    {:ok, pid} = Wasmex.start_link(%{store: store, module: state.module})
    {:ok, memory} = Wasmex.memory(pid)
    %{state | instance: %{pid: pid, store: store, memory: memory}}
  end

  defp transform(%{pid: pid, store: store, memory: memory}, src) do
    with {:ok, [ptr]} <- Wasmex.call_function(pid, "vv_input", [byte_size(src)], @timeout),
         :ok <- Wasmex.Memory.write_binary(store, memory, ptr, src),
         {:ok, [status]} <- Wasmex.call_function(pid, "vv_run", [], @timeout),
         {:ok, out} <- output(pid, store, memory, 1),
         {:ok, err} <- output(pid, store, memory, 2) do
      {:ok, {out, status, err}}
    end
  end

  defp output(pid, store, memory, fd) do
    with {:ok, [ptr]} <- Wasmex.call_function(pid, "vv_output", [fd], @timeout),
         {:ok, [len]} <- Wasmex.call_function(pid, "vv_output_len", [fd], @timeout) do
      {:ok, Wasmex.Memory.read_binary(store, memory, ptr, len)}
    end
  end

  defp format(reason) when is_binary(reason), do: reason
  defp format(reason), do: inspect(reason)
end

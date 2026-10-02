defmodule Moonflower.Look.Run do
  @moduledoc """
  One look: a fresh instance of the loaded module, given the page on stdin and read from stdout, under fuel and a
  memory cap, with no directory, environment or arguments. Runs in the look node (`Moonflower.Look.Node`).
  """
  alias Wasmex.{Pipe, Store, StoreLimits, StoreOrCaller}
  alias Wasmex.Wasi.WasiOptions

  @memory 256 * 1024 * 1024

  @doc "What the module may reach: nothing but its own stdin, stdout and stderr."
  def wasi_options, do: %WasiOptions{args: [], env: %{}, preopen: []}

  @doc "`{:ok, stdout}`, `{:error, :too_costly}` (out of fuel or memory) or `{:error, :failed}`."
  def run(%{engine: engine, precompiled: precompiled}, input, fuel, timeout) do
    {:ok, stdin} = Pipe.new()
    {:ok, stdout} = Pipe.new()
    {:ok, stderr} = Pipe.new()
    Pipe.write(stdin, input)
    Pipe.seek(stdin, 0)

    wasi = %{wasi_options() | stdin: stdin, stdout: stdout, stderr: stderr}
    {:ok, store} = Store.new_wasi(wasi, %StoreLimits{memory_size: @memory}, engine)
    :ok = StoreOrCaller.set_fuel(store, fuel)
    {:ok, module} = Wasmex.Module.unsafe_deserialize(precompiled, engine)
    # instantiating runs the module's start functions too, so fuel can run out before _start
    result =
      case GenServer.start(Wasmex, %{store: store, module: module, imports: %{}, links: []}) do
        {:ok, pid} -> call(pid, timeout)
        {:error, why} -> {:error, why}
      end

    case result do
      {:ok, _} ->
        Pipe.seek(stdout, 0)
        {:ok, Pipe.read(stdout)}

      {:error, why} ->
        Pipe.seek(stderr, 0)
        costly?(why, Pipe.read(stderr), StoreOrCaller.get_fuel(store))
    end
  end

  defp call(pid, timeout) do
    Wasmex.call_function(pid, :_start, [], timeout)
  catch
    :exit, _ -> {:error, :timeout}
  after
    if Process.alive?(pid), do: GenServer.stop(pid, :normal, 1_000)
  end

  defp costly?(why, err, fuel) do
    said = inspect(why) <> err

    cond do
      match?({:ok, 0}, fuel) or said =~ ~r/fuel|memory allocation|out of memory/i ->
        {:error, :too_costly}

      why == :timeout ->
        {:error, :too_costly}

      true ->
        {:error, :failed}
    end
  end
end

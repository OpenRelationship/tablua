defmodule VolvoxServer.Computer.Programs do
  @moduledoc """
  The computer's programs: WASI modules every computer shares, compiled once
  per node and kept in `:persistent_term`. `run(name, args, stdin, disk)` runs
  one in a fresh store of its own (memory capped at #{div(512 * 1024 * 1024, 1_048_576)} MB) against the
  kernel (`Computer.Wasi`) and gives back `{code, stdout, stderr}`.

  The modules are what `just build-script computer` writes in the Volvox repo
  (config `programs:`): `js.wasm` (QuickJS-ng), `python.wasm` (CPython),
  `sqlite3.wasm`. A name with no module is `:unknown`.
  """
  alias VolvoxServer.Computer.Wasi

  @memory 512 * 1024 * 1024
  @timeout 120_000

  def names do
    dir()
    |> File.ls()
    |> case do
      {:ok, files} ->
        for f <- files, String.ends_with?(f, ".wasm"), do: String.trim_trailing(f, ".wasm")

      _ ->
        []
    end
    |> Enum.sort()
  end

  def run(name, args, stdin, disk, env \\ %{}) do
    with {:ok, {engine, module}} <- compiled(name) do
      config = %{
        disk: disk,
        args: [name | args],
        env: Map.merge(%{"HOME" => "/", "PWD" => "/"}, env),
        stdin: stdin,
        owner: self()
      }

      {:ok, store} = Wasmex.Store.new(%Wasmex.StoreLimits{memory_size: @memory}, engine)

      {:ok, pid} =
        Wasmex.start_link(%{store: store, module: module, imports: Wasi.imports(module, config)})

      result =
        try do
          r = Wasmex.call_function(pid, "_start", [], @timeout)

          # the reply comes from the NIF, the output from the instance's process: a call to that process
          # answers only after everything it sent before
          _ = Wasmex.module(pid)
          r
        after
          GenServer.stop(pid)
        end

      {out, err} = drain(<<>>, <<>>)
      code = exit_code(result)
      {code, out, err}
    end
  end

  # the output arrives as messages while the program runs; the exit code too when it calls proc_exit
  defp drain(out, err) do
    receive do
      {:wasi_out, 1, bytes} -> drain(out <> bytes, err)
      {:wasi_out, 2, bytes} -> drain(out, err <> bytes)
    after
      0 -> {out, err}
    end
  end

  defp exit_code(result) do
    receive do
      {:wasi_exit, code} -> code
    after
      0 -> if match?({:ok, _}, result), do: 0, else: 134
    end
  end

  defp compiled(name) do
    key = {__MODULE__, name}

    case :persistent_term.get(key, nil) do
      nil ->
        path = Path.join(dir(), name <> ".wasm")

        if File.regular?(path) do
          {:ok, engine} = Wasmex.Engine.new(%Wasmex.EngineConfig{})
          {:ok, store} = Wasmex.Store.new(nil, engine)
          {:ok, module} = Wasmex.Module.compile(store, File.read!(path))
          :persistent_term.put(key, {engine, module})
          {:ok, {engine, module}}
        else
          :unknown
        end

      compiled ->
        {:ok, compiled}
    end
  end

  defp dir, do: Application.fetch_env!(:volvox_server, :programs)
end

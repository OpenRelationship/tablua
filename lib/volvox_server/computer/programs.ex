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
  @table :computer_modules
  @own 64

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
    with {:ok, module} <- compiled(name), do: start(module, [name | args], stdin, disk, env)
  end

  @doc """
  A module from the computer's own disk (one the agent built or fetched), run as
  a program: `argv0` is how it was named. Modules are compiled once per content,
  the latest #{64} kept.
  """
  def run_bytes(bytes, argv0, args, stdin, disk, env \\ %{}) do
    case own(bytes) do
      {:ok, module} -> start(module, [argv0 | args], stdin, disk, env)
      {:error, why} -> {126, "", "#{argv0}: not a program this computer can run: #{why}\n"}
    end
  end

  @doc "Whether bytes are a WebAssembly module."
  def wasm?(<<0, "asm", _::binary>>), do: true
  def wasm?(_), do: false

  defp start(module, argv, stdin, disk, env) do
    config = %{
      disk: disk,
      args: argv,
      env: Map.merge(%{"HOME" => "/", "PWD" => "/"}, env),
      stdin: stdin,
      owner: self()
    }

    {:ok, store} = Wasmex.Store.new(%Wasmex.StoreLimits{memory_size: @memory}, engine())

    case Wasmex.start_link(%{store: store, module: module, imports: Wasi.imports(module, config)}) do
      {:ok, pid} ->
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

        case exit_code(result) do
          {code, nil} -> {code, out, err}
          {code, why} -> {code, out, err <> "#{hd(argv)}: #{why}\n"}
        end

      {:error, why} ->
        {126, "", "#{hd(argv)}: #{inspect(why)}\n"}
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

  # {code, why}: a program that stopped by itself has no why; one that trapped says how
  defp exit_code(result) do
    receive do
      {:wasi_exit, code} -> {code, nil}
    after
      0 ->
        case result do
          {:ok, _} -> {0, nil}
          {:error, why} -> {134, why |> to_string() |> String.split("\n") |> hd()}
        end
    end
  end

  defp compiled(name) do
    key = {__MODULE__, name}

    case :persistent_term.get(key, nil) do
      nil ->
        path = Path.join(dir(), name <> ".wasm")

        if File.regular?(path) do
          {:ok, module} = compile(File.read!(path))
          :persistent_term.put(key, module)
          {:ok, module}
        else
          :unknown
        end

      module ->
        {:ok, module}
    end
  end

  # the agents' own modules: by content, in a table that keeps the latest @own
  defp own(bytes) do
    hash = :crypto.hash(:sha256, bytes)

    case :ets.lookup(@table, hash) do
      [{^hash, module, _}] ->
        :ets.update_element(@table, hash, {3, System.monotonic_time()})
        {:ok, module}

      [] ->
        with {:ok, module} <- compile(bytes) do
          if :ets.info(@table, :size) >= @own do
            {old, _, _} =
              :ets.foldl(
                fn {_, _, t} = e, acc -> if acc == nil or t < elem(acc, 2), do: e, else: acc end,
                nil,
                @table
              )

            :ets.delete(@table, old)
          end

          :ets.insert(@table, {hash, module, System.monotonic_time()})
          {:ok, module}
        end
    end
  end

  @doc "The table of the agents' own compiled modules; made once by the application."
  def table, do: :ets.new(@table, [:named_table, :public, :set])

  defp compile(bytes) do
    {:ok, store} = Wasmex.Store.new(nil, engine())

    case Wasmex.Module.compile(store, bytes) do
      {:ok, module} -> {:ok, module}
      {:error, why} -> {:error, why |> to_string() |> String.split("\n") |> hd()}
    end
  end

  # one engine for every computer, so a compiled module runs in any of them
  defp engine do
    case :persistent_term.get({__MODULE__, :engine}, nil) do
      nil ->
        {:ok, engine} = Wasmex.Engine.new(%Wasmex.EngineConfig{})
        :persistent_term.put({__MODULE__, :engine}, engine)
        engine

      engine ->
        engine
    end
  end

  defp dir, do: Application.fetch_env!(:volvox_server, :programs)
end

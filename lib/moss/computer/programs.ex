defmodule Moss.Computer.Programs do
  @moduledoc """
  The computer's programs: WASI modules every computer shares, compiled once
  per node and kept in `:persistent_term`. `run(name, args, stdin, disk)` runs
  one in a fresh store of its own (memory capped at #{div(512 * 1024 * 1024, 1_048_576)} MB) against the
  kernel (`Computer.Wasi`) and gives back `{code, stdout, stderr}`.

  The modules are what `just build-script computer` writes in the Arock repo
  (config `programs:`): `js.wasm` (QuickJS-ng), `python.wasm` (CPython),
  `sqlite3.wasm`, `lua.wasm`, `cc.wasm` (xcc). A name with no module is `:unknown`.
  """
  alias Moss.Computer.{Clang, Disk, Files, Go, Wasi}

  @memory 512 * 1024 * 1024
  @timeout 120_000
  @table :computer_modules
  @own 64

  # names another program's module answers to, by its first argument
  @as %{"clang++" => "clang", "wasm-ld" => "clang"}

  def names do
    dir()
    |> File.ls()
    |> case do
      {:ok, files} ->
        for f <- files, String.ends_with?(f, ".wasm"), do: String.trim_trailing(f, ".wasm")

      _ ->
        []
    end
    |> then(fn have -> have ++ for({a, of} <- @as, of in have, do: a) end)
    |> then(fn have -> if "go-compile" in have, do: ["go" | have], else: have end)
    |> Enum.sort()
  end

  # what a program needs set to find its own files under /usr
  @env %{
    "go-compile" => %{"GOROOT" => "/usr/lib/go", "GOOS" => "wasip1", "GOARCH" => "wasm"},
    "go-link" => %{"GOROOT" => "/usr/lib/go", "GOOS" => "wasip1", "GOARCH" => "wasm"},
    "python" => %{"PYTHONHOME" => "/usr/local", "PYTHONDONTWRITEBYTECODE" => "1"},
    "zig" => %{"ZIG_LIB_DIR" => "/usr/lib/zig", "ZIG_GLOBAL_CACHE_DIR" => "/home/.cache/zig"}
  }

  @doc "Compiles every program at boot, side by side, so no agent's first command waits on it."
  def warm do
    names()
    |> Enum.map(&Map.get(@as, &1, &1))
    |> Enum.reject(&(&1 == "go"))
    |> Enum.uniq()
    |> Task.async_stream(&compiled/1, timeout: :infinity, ordered: false)
    |> Stream.run()
  end

  def run(name, args, stdin, disk, env \\ %{}) do
    exec = fn argv0, args -> exec(argv0, args, stdin, disk, env) end

    cond do
      name == "go" and has?("go-compile") ->
        Go.run(args, %{
          exec: exec,
          cwd: env["PWD"] || "/home",
          disk: disk,
          start: fn path, given ->
            case Disk.read(disk, path) do
              {:ok, bytes} -> run_bytes(bytes, Path.basename(path), given, stdin, disk, env)
              _ -> {1, "", "go: the build left no program\n"}
            end
          end
        })

      name in ["clang", "clang++"] and has?("clang") ->
        Clang.run(name, args, exec, fn paths -> Enum.each(paths, &Disk.remove(disk, &1)) end)

      true ->
        exec.(name, given(name, args))
    end
  end

  defp exec(argv0, args, stdin, disk, env) do
    env = Map.merge(Map.get(@env, argv0, %{}), env)

    with {:ok, module} <- compiled(Map.get(@as, argv0, argv0)),
         do: start(module, [argv0 | args], stdin, disk, env)
  end

  defp has?(name), do: File.regular?(Path.join(dir(), name <> ".wasm"))

  # Zig's wasm backend cannot build compiler_rt itself: the prebuilt one is linked in, and no entry is added
  # (std's start code exports _start), as zigtools' playground runs it
  defp given("zig", [build | _] = args)
       when build in ["build-exe", "build-lib", "build-obj", "test"] do
    if "-fno-compiler-rt" in args,
      do: args,
      else: args ++ ["/usr/lib/zig/libcompiler_rt.a", "-fno-compiler-rt", "-fno-entry"]
  end

  defp given(_name, args), do: args

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
            # answers only after everything it sent before. In that process too, where the open files live, a
            # program that ended without closing them (by exit, a trap or a plain return) has them written
            _ = Wasmex.module(pid)
            flush(pid, disk)
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

  defp flush(pid, disk) do
    :sys.replace_state(pid, fn s -> tap(s, fn _ -> Files.flush_all(disk) end) end, 10_000)
  catch
    :exit, _ -> :ok
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

  # one engine for every computer, so a compiled module runs in any of them; optimized, since a program is
  # compiled once per node and run many times (a Lua loop runs 1.6x faster for a few ms more compiling)
  defp engine do
    case :persistent_term.get({__MODULE__, :engine}, nil) do
      nil ->
        {:ok, engine} = Wasmex.Engine.new(%Wasmex.EngineConfig{cranelift_opt_level: :speed})
        :persistent_term.put({__MODULE__, :engine}, engine)
        engine

      engine ->
        engine
    end
  end

  defp dir, do: Application.fetch_env!(:moss, :programs)
end

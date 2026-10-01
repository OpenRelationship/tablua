defmodule Moss.Computer.Wasi do
  @moduledoc """
  The computer's kernel: WASI preview 1, answered in Elixir. `imports(module,
  config)` gives wasmex an import for every `wasi_snapshot_preview1` call the
  module names, with the module's own signature; a call the kernel does not
  answer returns ENOSYS. Files are the computer's disk (`Computer.Files`);
  nothing reaches the node's own filesystem, a process, or a socket. A
  program's web requests (`fetch` in `js`) go through `Computer.Http`.

  `config`: `%{disk, args, env, stdin, owner}`. Output goes to `owner` as
  `{:wasi_out, fd, bytes}` as it is written, the exit code as `{:wasi_exit, code}`.

  The calls run in the wasmex instance's own process, one at a time, so the
  open files live in that process's dictionary (`Computer.Files`).
  """
  import Bitwise
  alias Moss.Computer.{Files, Http}
  alias Wasmex.Memory

  @ns "wasi_snapshot_preview1"
  @enosys 52
  @einval 28

  def imports(module, config) do
    all = Wasmex.Module.imports(module)

    # WASI's calls, and the `moss` module's for the web (Computer.Http) when the program names it
    for {ns, answer} <- [{@ns, &call/2}, {"moss", &Http.call/2}],
        wanted = Map.get(all, ns),
        into: %{} do
      {ns,
       for {name, {:fn, params, results}} <- wanted, into: %{} do
         {name, {:fn, params, results, wrap(answer.(name, config), length(params), results)}}
       end}
    end
  end

  # wasmex calls fn(ctx, a, b, ...): one function per arity, around call(name)'s fn(ctx, [args])
  defp wrap(fun, arity, results) do
    reply = fn ctx, args ->
      r = fun.(ctx, args)
      if results == [], do: nil, else: r
    end

    case arity do
      0 -> fn ctx -> reply.(ctx, []) end
      1 -> fn ctx, a -> reply.(ctx, [a]) end
      2 -> fn ctx, a, b -> reply.(ctx, [a, b]) end
      3 -> fn ctx, a, b, c -> reply.(ctx, [a, b, c]) end
      4 -> fn ctx, a, b, c, d -> reply.(ctx, [a, b, c, d]) end
      5 -> fn ctx, a, b, c, d, e -> reply.(ctx, [a, b, c, d, e]) end
      6 -> fn ctx, a, b, c, d, e, f -> reply.(ctx, [a, b, c, d, e, f]) end
      7 -> fn ctx, a, b, c, d, e, f, g -> reply.(ctx, [a, b, c, d, e, f, g]) end
      8 -> fn ctx, a, b, c, d, e, f, g, h -> reply.(ctx, [a, b, c, d, e, f, g, h]) end
      9 -> fn ctx, a, b, c, d, e, f, g, h, i -> reply.(ctx, [a, b, c, d, e, f, g, h, i]) end
    end
  end

  # -- memory ------------------------------------------------------------------------------------

  def read(ctx, ptr, len), do: Memory.read_binary(ctx.caller, ctx.memory, ptr, len)
  def write(ctx, ptr, bytes), do: Memory.write_binary(ctx.caller, ctx.memory, ptr, bytes)
  def u32(ctx, ptr, v), do: write(ctx, ptr, <<v::little-32>>)
  def u64(ctx, ptr, v), do: write(ctx, ptr, <<v::little-64>>)

  @doc "The buffers of an iovec list: [{ptr, len}]."
  def iovs(ctx, ptr, n) do
    bytes = read(ctx, ptr, n * 8)
    for <<p::little-32, l::little-32 <- bytes>>, do: {p, l}
  end

  # -- the calls ---------------------------------------------------------------------------------

  defp call("args_sizes_get", c), do: fn ctx, [count, size] -> sizes(ctx, c.args, count, size) end
  defp call("args_get", c), do: fn ctx, [ptrs, buf] -> strings(ctx, c.args, ptrs, buf) end

  defp call("environ_sizes_get", c),
    do: fn ctx, [count, size] -> sizes(ctx, env(c), count, size) end

  defp call("environ_get", c), do: fn ctx, [ptrs, buf] -> strings(ctx, env(c), ptrs, buf) end

  defp call("clock_time_get", _c) do
    fn ctx, [id, _precision, ptr] ->
      ns =
        if id == 0,
          do: System.os_time(:nanosecond),
          else: System.monotonic_time(:nanosecond) &&& 0x7FFFFFFFFFFFFFFF

      u64(ctx, ptr, ns)
      0
    end
  end

  defp call("clock_res_get", _c), do: fn ctx, [_id, ptr] -> u64(ctx, ptr, 1000) && 0 end

  defp call("random_get", _c),
    do: fn ctx, [ptr, len] -> write(ctx, ptr, :crypto.strong_rand_bytes(len)) && 0 end

  defp call("sched_yield", _c), do: fn _ctx, [] -> 0 end

  defp call("proc_exit", c) do
    fn _ctx, [code] ->
      send(c.owner, {:wasi_exit, code})
      raise "exit #{code}"
    end
  end

  defp call("proc_raise", c) do
    fn _ctx, [sig] ->
      send(c.owner, {:wasi_exit, 128 + sig})
      raise "signal #{sig}"
    end
  end

  # every subscription answers at once: a clock is taken as passed, a read or write as ready
  defp call("poll_oneoff", _c) do
    fn ctx, [subs, events, n, count] ->
      out =
        for <<user::little-64, tag::8, _::binary-size(39) <- read(ctx, subs, n * 48)>>,
          into: <<>> do
          <<user::little-64, 0::little-16, tag::8, 0::8, 0::32, 0::little-64, 0::little-16,
            0::48>>
        end

      write(ctx, events, out)
      u32(ctx, count, n)
      0
    end
  end

  defp call(name, c) do
    if Files.answers?(name),
      do: fn ctx, args -> Files.call(name, ctx, args, c) end,
      else: fn _ctx, _ -> @enosys end
  end

  defp env(c), do: Enum.map(c.env, fn {k, v} -> "#{k}=#{v}" end)

  defp sizes(ctx, list, count, size) do
    u32(ctx, count, length(list))
    u32(ctx, size, Enum.reduce(list, 0, &(byte_size(&1) + 1 + &2)))
    0
  end

  defp strings(ctx, list, ptrs, buf) do
    Enum.reduce(list, {ptrs, buf}, fn s, {p, b} ->
      u32(ctx, p, b)
      write(ctx, b, s <> <<0>>)
      {p + 4, b + byte_size(s) + 1}
    end)

    0
  rescue
    _ -> @einval
  end
end

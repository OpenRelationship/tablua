defmodule Moss.Computer.Script do
  @moduledoc """
  The computer's language: Lua, run on the BEAM by tv-labs `lua`, with the
  computer's own system as its library (`priv/lua/computer.lua`): `fs` over
  the disk, `http` through the web rules (`Computer.Net`), `json`, `mail`,
  `print`/`io` on the command's own stdin and stdout, and `require` from the
  disk. There is nothing else to reach: no WebAssembly, no native code, no
  node file, socket or process.

      lua hello.lua [args...]     a script on the disk; `arg[1]`... are its args
      lua -e '<code>' [args...]   a line of code

  Every run is a process of its own, killed past #{div(64 * 1024 * 1024, 1_048_576)} MB of heap or
  #{div(120_000, 1000)} s, and its VM stops itself past #{div(500_000_000, 1_000_000)} million instructions or
  a #{div(16 * 1024 * 1024, 1_048_576)} MB string; output past #{div(1024 * 1024, 1024)} KB ends it too.
  """
  alias Moss.Mail
  alias Moss.Computer.{Disk, Net}

  @heap_words div(64 * 1024 * 1024, :erlang.system_info(:wordsize))
  @timeout 120_000
  @instructions 500_000_000
  @string_bytes 16 * 1024 * 1024
  @out_bytes 1024 * 1024

  def names, do: ["lua"]

  def run(["-e", code | args], stdin, state),
    do: start(code, "(command line)", args, stdin, state)

  def run([file | args], stdin, state) do
    case Disk.read(state.disk, Disk.norm(file, state.cwd)) do
      {:ok, code} -> start(code, file, args, stdin, state)
      {:error, :eisdir} -> {1, "", "lua: #{file}: is a folder\n", state}
      {:error, _} -> {1, "", "lua: #{file}: no such file\n", state}
    end
  end

  def run([], _stdin, state), do: {2, "", "lua: give a file, or -e '<code>'\n", state}

  defp start(code, name, args, stdin, state) do
    me = self()
    ref = make_ref()
    callers = [me | Process.get(:"$callers", [])]

    {pid, mon} =
      spawn_monitor(fn ->
        # as a Task's: whoever stands behind the computer stands behind its run
        Process.put(:"$callers", callers)
        Process.flag(:max_heap_size, %{size: @heap_words, kill: true, error_logger: false})
        send(me, {ref, eval(code, name, args, stdin, state)})
      end)

    receive do
      {^ref, {status, out, err}} ->
        Process.demonitor(mon, [:flush])
        {status, out, err, state}

      {:DOWN, ^mon, :process, ^pid, :killed} ->
        {137, "", "lua: out of memory (#{div(@heap_words * 8, 1_048_576)} MB)\n", state}

      {:DOWN, ^mon, :process, ^pid, why} ->
        {1, "", "lua: #{inspect(why)}\n", state}
    after
      @timeout ->
        Process.exit(pid, :kill)
        {124, "", "lua: stopped after #{div(@timeout, 1000)} s\n", state}
    end
  end

  # In the run's own process: the VM, its library bound to this computer, the code.
  defp eval(code, name, args, stdin, state) do
    Process.put(:out, {[], 0})
    Process.put(:err, [])

    lua =
      Lua.new(
        max_instructions: Application.get_env(:moss, :script_instructions, @instructions),
        max_string_bytes: @string_bytes,
        exclude: [[:load]]
      )
      |> bind(stdin, state)
      |> Lua.set!([:__args], args)

    {_, lua} = Lua.eval!(lua, prelude())

    # __main (computer.lua) runs the code under xpcall: an error is printed, os.exit(n) is a status
    status =
      try do
        case Lua.call_function(lua, [:__main], [code, name]) do
          {:ok, [n | _], _} when is_number(n) -> trunc(n)
          {:ok, _, _} -> 0
          {:error, e, _} -> fail("lua: #{Exception.message(e)}\n")
        end
      catch
        :throw, :too_much_output -> fail("lua: more than #{div(@out_bytes, 1024)} KB of output\n")
      end

    {out, _} = Process.get(:out)

    {status, IO.iodata_to_binary(Enum.reverse(out)),
     IO.iodata_to_binary(Enum.reverse(Process.get(:err)))}
  end

  defp out(bytes) do
    {acc, n} = Process.get(:out)
    n = n + byte_size(bytes)
    if n > @out_bytes, do: throw(:too_much_output)
    Process.put(:out, {[bytes | acc], n})
    []
  end

  defp err(bytes) do
    Process.put(:err, [bytes | Process.get(:err)])
    []
  end

  # a run that failed outside the script's own xpcall: its message, status 1
  defp fail(message) do
    err(message)
    1
  end

  defp bind(lua, stdin, state) do
    disk = state.disk
    cwd = state.cwd
    path = fn p -> Disk.norm(p, cwd) end

    lua
    |> fun(:write, fn [s | _] -> out(to_string(s)) end)
    |> fun(:ewrite, fn [s | _] -> err(to_string(s)) end)
    |> fun(:stdin, fn _ -> [stdin] end)
    |> fun(:cwd, fn _ -> [cwd] end)
    |> fun(:now, fn _ -> [System.os_time(:millisecond) / 1000] end)
    |> fun(:read, fn [p | _] -> result(Disk.read(disk, path.(p))) end)
    |> fun(:write_file, fn [p, data | _] ->
      result(Disk.write(disk, path.(p), to_string(data)))
    end)
    |> fun(:mkdir, fn [p | _] -> result(Disk.mkdir_p(disk, path.(p))) end)
    |> fun(:remove, fn [p | rest] ->
      result(Disk.remove(disk, path.(p), List.first(rest) == true))
    end)
    |> fun(:rename, fn [a, b | _] -> result(Disk.rename(disk, path.(a), path.(b))) end)
    |> fun(:stat, fn [p | _] -> stat(Disk.stat(disk, path.(p))) end)
    |> list_fun(disk, path)
    |> http_fun()
    |> json_funs()
    |> mail_fun(state)
  end

  defp fun(lua, name, f), do: Lua.set!(lua, [:__sys, name], f)

  defp result(:ok), do: [true]
  defp result({:ok, v}), do: [v]
  defp result({:error, why}), do: [nil, to_string(why)]

  defp stat({:ok, s}), do: [s.dir, s.size, s.mtime]
  defp stat({:error, why}), do: [nil, to_string(why)]

  defp list_fun(lua, disk, path) do
    fun(lua, :list, fn [p | _], lua ->
      case Disk.list(disk, path.(p)) do
        {:ok, entries} ->
          {t, lua} = Lua.encode!(lua, Enum.map(entries, & &1.name))
          {[t], lua}

        {:error, why} ->
          {[nil, to_string(why)], lua}
      end
    end)
  end

  # http.request{ method, url, headers, body } -> { status, body, url, headers }, under the web rules
  defp http_fun(lua) do
    fun(lua, :http, fn [{:tref, _} = t | _], lua ->
      req = Map.new(Lua.decode!(lua, t))
      headers = for {k, v} <- Map.new(req["headers"] || []), do: {to_string(k), to_string(v)}
      method = String.upcase(req["method"] || "GET")

      if method in ~w(GET POST PUT PATCH DELETE HEAD) do
        case Net.get(req["url"] || "", method: method, headers: headers, body: req["body"]) do
          {:ok, r} ->
            hs = for {k, v} <- r.headers, do: {k, Enum.join(List.wrap(v), ", ")}

            {t, lua} =
              Lua.encode!(lua, %{
                "status" => r.status,
                "body" => r.body,
                "url" => r.url,
                "headers" => Map.new(hs)
              })

            {[t], lua}

          {:error, why} ->
            {[nil, to_string(why)], lua}
        end
      else
        {[nil, "no such method: #{method}"], lua}
      end
    end)
  end

  defp json_funs(lua) do
    lua
    |> fun(:json_decode, fn [s | _], lua ->
      case Jason.decode(to_string(s)) do
        {:ok, v} ->
          {t, lua} = Lua.encode!(lua, v)
          {[t], lua}

        {:error, e} ->
          {[nil, Exception.message(e)], lua}
      end
    end)
    |> fun(:json_encode, fn [v | _], lua -> {[Jason.encode!(json(Lua.decode!(lua, v)))], lua} end)
  end

  # A decoded Lua value as JSON: a table with keys 1..n is an array, any other an object.
  defp json(pairs) when is_list(pairs) do
    keys = Enum.map(pairs, &elem(&1, 0))

    if pairs != [] and Enum.sort(keys) == Enum.to_list(1..length(keys)),
      do: pairs |> Enum.sort() |> Enum.map(&json(elem(&1, 1))),
      else: Map.new(pairs, fn {k, v} -> {to_string(k), json(v)} end)
  end

  defp json(v), do: v

  # mail.send(to, subject, body) -> id, or nil and why; along the routes a person set (Moss.Mail)
  defp mail_fun(lua, state) do
    fun(lua, :mail, fn [to, subject, body | _] ->
      case Mail.post(state.id, to_string(to), to_string(subject), to_string(body)) do
        {:refused, why} -> [nil, "refused: #{why}"]
        {_, id} -> [id]
      end
    end)
  end

  defp prelude, do: :persistent_term.get({__MODULE__, :prelude}, nil) || load_prelude()

  defp load_prelude do
    src = File.read!(Path.join(:code.priv_dir(:moss), "lua/computer.lua"))
    :persistent_term.put({__MODULE__, :prelude}, src)
    src
  end
end

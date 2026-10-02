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
  alias Moss.Computer.Disk
  alias Moss.Computer.Script.Sql

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
    case spawn_run(fn -> eval(code, name, args, stdin, state) end) do
      {:ok, {status, out, err}} -> {status, out, err, state}
      {:error, status, err} -> {status, "", err, state}
    end
  end

  @doc """
  One request to the computer's app: its `.lui` page (`Moss.Computer.Pages`), run in its app's folder, or
  `/home/app.lua` while the gallery moves to apps (see `__serve` in computer.lua):
  `req` is `%{"method", "path", "query", "form", "headers"}`; the answer is
  `{status, headers, body, err}`, under the same bounds as a command's run.
  """
  def serve(req, state) do
    {req, cwd, app} = Moss.Computer.Pages.request(req, state.disk)

    case spawn_run(fn -> eval_serve(req, %{state | cwd: cwd}) end) do
      {:ok, answer} -> Moss.Computer.Pages.from_app(answer, app)
      {:error, _status, err} -> {500, %{}, "the app stopped: " <> err, err}
    end
  end

  # the run in a process of its own, bounded in heap and time
  defp spawn_run(f) do
    me = self()
    ref = make_ref()
    callers = [me | Process.get(:"$callers", [])]

    {pid, mon} =
      spawn_monitor(fn ->
        # as a Task's: whoever stands behind the computer stands behind its run
        Process.put(:"$callers", callers)
        Process.flag(:max_heap_size, %{size: @heap_words, kill: true, error_logger: false})
        send(me, {ref, f.()})
      end)

    receive do
      {^ref, result} ->
        Process.demonitor(mon, [:flush])
        {:ok, result}

      {:DOWN, ^mon, :process, ^pid, :killed} ->
        {:error, 137, "lua: out of memory (#{div(@heap_words * 8, 1_048_576)} MB)\n"}

      {:DOWN, ^mon, :process, ^pid, why} ->
        {:error, 1, "lua: #{inspect(why)}\n"}
    after
      @timeout ->
        Process.exit(pid, :kill)
        {:error, 124, "lua: stopped after #{div(@timeout, 1000)} s\n"}
    end
  end

  # the VM, its library bound to this computer, the prelude evaluated
  defp vm(args, stdin, state) do
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
      |> Lua.set!([:__named], Map.get(state, :tool_args, %{}))

    {_, lua} = Lua.eval!(lua, prelude())
    lua
  end

  # In the run's own process: the code under __main (computer.lua), which prints an error and turns os.exit(n)
  # into a status.
  defp eval(code, name, args, stdin, state) do
    lua = vm(args, stdin, state)

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

    :ok = Sql.close_all(state.disk)
    {out, _} = Process.get(:out)

    {status, IO.iodata_to_binary(Enum.reverse(out)),
     IO.iodata_to_binary(Enum.reverse(Process.get(:err)))}
  end

  defp eval_serve(req, state) do
    lua = vm([], "", state)
    {t, lua} = Lua.encode!(lua, req)

    answer =
      try do
        case Lua.call_function(lua, [:__serve], [t]) do
          {:ok, [status, headers, body | _], lua} ->
            {trunc(status),
             Map.new(Lua.decode!(lua, headers), fn {k, v} -> {to_string(k), to_string(v)} end),
             to_string(body)}

          {:error, e, _} ->
            fail("lua: #{Exception.message(e)}\n")
            {500, %{}, "the app failed"}
        end
      catch
        :throw, :too_much_output ->
          {500, %{}, "the app printed more than #{div(@out_bytes, 1024)} KB"}
      end

    :ok = Sql.close_all(state.disk)
    {status, headers, body} = answer

    {status, headers, body, IO.iodata_to_binary(Enum.reverse(Process.get(:err)))}
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
    |> Moss.Computer.Script.Http.bind(state)
    |> json_funs()
    |> mail_fun(state)
    |> db_funs(disk, path)
    |> fun(:module, fn [n | _] -> [builtin(to_string(n))] end)
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

  # mail.send(to, subject, body) -> id, or nil and why; along the routes a person set (Moss.Mail), and logged by
  # the computer when the run is over (Moss.Computer.mail/4)
  defp mail_fun(lua, state) do
    fun(lua, :mail, fn [to, subject, body | _] ->
      case Moss.Computer.mail(state.id, to_string(to), to_string(subject), to_string(body)) do
        {:refused, why} -> [nil, "refused: #{why}"]
        {_, id} -> [id]
      end
    end)
  end

  # db.open(path) -> handle; db_exec(h, sql, params) -> rows, changes; db_save(h); db_close(h). A statement's work
  # is spent from the run's own instruction budget (Moss.Sql.Budget), so SQL stops where Lua would.
  defp db_funs(lua, disk, path) do
    lua
    |> fun(:db_open, fn [p | _] -> result(Sql.open(disk, path.(p))) end)
    |> fun(:db_save, fn [h | _] -> result(Sql.save(disk, h)) end)
    |> fun(:db_close, fn [h | _] -> result(Sql.close(disk, h)) end)
    |> fun(:db_exec, fn [h, sql | rest], lua ->
      params =
        case rest do
          [{:tref, _} = t | _] -> lua |> Lua.decode!(t) |> Enum.sort() |> Enum.map(&elem(&1, 1))
          _ -> []
        end

      st = lua.state

      left =
        if st.max_instructions == :infinity,
          do: :infinity,
          else: st.max_instructions - st.instruction_count

      {answer, spent} =
        case Sql.exec(disk, h, to_string(sql), params, left) do
          {:ok, rows, changes, spent} -> {{:ok, rows, changes}, spent}
          {:error, why, spent} -> {{:error, why}, spent}
        end

      lua = %{lua | state: %{st | instruction_count: st.instruction_count + spent}}

      case answer do
        {:ok, rows, changes} ->
          {t, lua} = Lua.encode!(lua, rows)
          {[t, changes], lua}

        {:error, why} ->
          {[nil, to_string(why)], lua}
      end
    end)
  end

  @doc "`help lua`: the library as its files describe it, the opening comment of each."
  def reference do
    sdk = sdk() |> Enum.reject(fn {n, _} -> String.starts_with?(n, "shroomi") end) |> Enum.sort()
    Enum.map_join([prelude() | Enum.map(sdk, &elem(&1, 1))], "\n", &header/1)
  end

  @doc "`help shroomi`: how to publish, from Shroomi's own files."
  def shroomi_reference do
    m = sdk()
    Enum.map_join(~w(shroomi.lui shroomi.components shroomi.css), "\n", &header(m[&1]))
  end

  # a file's opening comment, as text
  defp header(src) do
    src
    |> String.split("\n")
    |> Enum.take_while(&String.starts_with?(&1, "--"))
    |> Enum.map_join(
      &(String.replace_prefix(&1, "-- ", "")
        |> String.replace_prefix("--", "")
        |> Kernel.<>("\n"))
    )
  end

  # The SDK's own modules, which `require` finds before the disk: priv/lua/sdk, and Shroomi (Arock PROJECT.md §16)
  # from its submodule as `shroomi` and `shroomi.<file>`
  defp builtin(name), do: Map.get(sdk(), name)

  defp sdk do
    :persistent_term.get({__MODULE__, :sdk}, nil) ||
      (fn ->
         own = Path.wildcard(Path.join(:code.priv_dir(:moss), "lua/sdk/*.lua"))
         m = Map.new(own, &{Path.basename(&1, ".lua"), File.read!(&1)})
         shroomi = Path.join(Moss.Lua.Sources.core(), "submodules/shroomi")

         m =
           for f <- Path.wildcard(shroomi <> "/*.lua"),
               base = Path.basename(f, ".lua"),
               not String.ends_with?(base, "_test"),
               into: m,
               do: {if(base == "init", do: "shroomi", else: "shroomi." <> base), File.read!(f)}

         :persistent_term.put({__MODULE__, :sdk}, m)
         m
       end).()
  end

  defp prelude, do: :persistent_term.get({__MODULE__, :prelude}, nil) || load_prelude()

  defp load_prelude do
    src = File.read!(Path.join(:code.priv_dir(:moss), "lua/computer.lua"))
    :persistent_term.put({__MODULE__, :prelude}, src)
    src
  end
end

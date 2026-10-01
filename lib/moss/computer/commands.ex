defmodule Moss.Computer.Commands do
  @moduledoc """
  The commands the computer's shell knows. `run(argv, stdin, state)` gives back
  `{code, out, err, state}`. Files and folders are the computer's disk; the text
  tools are `Computer.Text`, the web `Computer.Net`, the browser
  `Computer.Browser`, and `lua` the computer's language (`Computer.Script`).
  """
  alias Moss.Computer.{Browser, Disk, Mailbox, Net, Script, Text}

  @builtin ~w(cd pwd echo env export unset true false which help date sleep ls cat mkdir rm rmdir mv cp touch find tree)

  def names,
    do:
      Enum.sort(
        @builtin ++
          Text.names() ++ Net.names() ++ Browser.names() ++ ["mail"] ++ Script.names()
      )

  def run([name | args], stdin, state) do
    cond do
      name in @builtin ->
        builtin(name, args, stdin, state)

      name in Text.names() ->
        ok(Text.run(name, args, stdin, state), state)

      name in Net.names() ->
        Net.run(name, args, stdin, state)

      name in Browser.names() ->
        Browser.run(name, args, stdin, state)

      name == "mail" ->
        ok(Mailbox.run(args, stdin, state), state)

      name in Script.names() ->
        Script.run(args, stdin, state)

      true ->
        {127, "", "#{name}: command not found\n", state}
    end
  end

  defp ok({code, out, err}, state), do: {code, out, err, state}

  # -- the shell's own ---------------------------------------------------------------------------

  defp builtin("cd", args, _stdin, state) do
    to = Disk.norm(List.first(args) || state.env["HOME"] || "/", state.cwd)

    case Disk.stat(state.disk, to) do
      {:ok, %{dir: true}} -> {0, "", "", %{state | cwd: to}}
      {:ok, _} -> {1, "", "cd: #{to}: not a folder\n", state}
      _ -> {1, "", "cd: #{to}: no such folder\n", state}
    end
  end

  defp builtin("pwd", _args, _stdin, state), do: {0, state.cwd <> "\n", "", state}

  defp builtin("echo", args, _stdin, state) do
    {nl, args} = if List.first(args) == "-n", do: {"", tl(args)}, else: {"\n", args}
    {0, Enum.join(args, " ") <> nl, "", state}
  end

  defp builtin("env", _args, _stdin, state),
    do: {0, Enum.map_join(Enum.sort(state.env), fn {k, v} -> "#{k}=#{v}\n" end), "", state}

  defp builtin("export", args, _stdin, state) do
    env =
      Enum.reduce(args, state.env, fn a, env ->
        with [k, v] <- String.split(a, "=", parts: 2), do: Map.put(env, k, v), else: (_ -> env)
      end)

    {0, "", "", %{state | env: env}}
  end

  defp builtin("unset", args, _stdin, state),
    do: {0, "", "", %{state | env: Map.drop(state.env, args)}}

  defp builtin("true", _, _, state), do: {0, "", "", state}
  defp builtin("false", _, _, state), do: {1, "", "", state}

  defp builtin("help", _, _, state),
    do: {0, "commands: " <> Enum.join(names(), " ") <> "\n", "", state}

  defp builtin("date", _, _, state),
    do:
      {0, (DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_string()) <> "\n", "",
       state}

  defp builtin("sleep", [n | _], _, state) do
    Process.sleep(
      round(
        min(String.to_float(n <> if(String.contains?(n, "."), do: "", else: ".0")), 10.0) * 1000
      )
    )

    {0, "", "", state}
  rescue
    _ -> {1, "", "sleep: #{n}: not a number\n", state}
  end

  defp builtin("which", args, _, state) do
    found = Enum.filter(args, &(&1 in names()))

    {if(length(found) == length(args), do: 0, else: 1), Enum.map_join(found, &"/bin/#{&1}\n"), "",
     state}
  end

  # -- files and folders -------------------------------------------------------------------------

  defp builtin("ls", args, _stdin, state) do
    {flags, paths} = flags(args)
    long = String.contains?(flags, "l")
    all = String.contains?(flags, "a")
    paths = if paths == [], do: ["."], else: paths

    {outs, errs} =
      Enum.reduce(paths, {[], []}, fn p, {outs, errs} ->
        path = Disk.norm(p, state.cwd)

        case Disk.stat(state.disk, path) do
          {:ok, %{dir: true}} ->
            {:ok, kids} = Disk.list(state.disk, path)
            kids = if all, do: kids, else: Enum.reject(kids, &String.starts_with?(&1.name, "."))
            head = if length(paths) > 1, do: "#{p}:\n", else: ""
            {[head <> Enum.map_join(kids, &entry(&1, long)) | outs], errs}

          {:ok, s} ->
            {[entry(Map.put(s, :name, p), long) | outs], errs}

          _ ->
            {outs, ["ls: #{p}: no such file or folder\n" | errs]}
        end
      end)

    {if(errs == [], do: 0, else: 1), outs |> Enum.reverse() |> Enum.join("\n"),
     Enum.join(Enum.reverse(errs)), state}
  end

  defp builtin("cat", [], stdin, state), do: {0, stdin, "", state}

  defp builtin("cat", args, _stdin, state) do
    each(args, state, fn path ->
      case Disk.read(state.disk, path) do
        {:ok, data} -> {:out, data}
        {:error, :eisdir} -> {:err, "cat: #{path}: is a folder\n"}
        _ -> {:err, "cat: #{path}: no such file\n"}
      end
    end)
  end

  defp builtin("mkdir", args, _stdin, state) do
    {flags, paths} = flags(args)
    make = if String.contains?(flags, "p"), do: &Disk.mkdir_p/2, else: &Disk.mkdir/2
    each(paths, state, &done(make.(state.disk, &1), "mkdir", &1))
  end

  defp builtin("rm", args, _stdin, state) do
    {flags, paths} = flags(args)

    {all, force} =
      {String.contains?(flags, "r") or String.contains?(flags, "R"), String.contains?(flags, "f")}

    each(paths, state, fn path ->
      case Disk.stat(state.disk, path) do
        {:ok, %{dir: true}} when not all -> {:err, "rm: #{path}: is a folder (rm -r)\n"}
        {:ok, _} -> done(Disk.remove(state.disk, path, true), "rm", path)
        _ when force -> :ok
        _ -> {:err, "rm: #{path}: no such file\n"}
      end
    end)
  end

  defp builtin("rmdir", args, _stdin, state),
    do: each(args, state, &done(Disk.remove(state.disk, &1), "rmdir", &1))

  defp builtin("touch", args, _stdin, state) do
    each(args, state, fn path ->
      case Disk.read(state.disk, path) do
        {:ok, data} -> done(Disk.write(state.disk, path, data), "touch", path)
        {:error, :eisdir} -> :ok
        _ -> done(Disk.write(state.disk, path, ""), "touch", path)
      end
    end)
  end

  defp builtin(move, args, _stdin, state) when move in ["mv", "cp"] do
    {flags, paths} = flags(args)

    case Enum.map(paths, &Disk.norm(&1, state.cwd)) do
      list when length(list) >= 2 ->
        {sources, [to]} = Enum.split(list, -1)
        into = match?({:ok, %{dir: true}}, Disk.stat(state.disk, to))

        errs =
          for from <- sources,
              target = if(into, do: Path.join(to, Path.basename(from)), else: to),
              r =
                if(move == "mv",
                  do: Disk.rename(state.disk, from, target),
                  else: copy(state.disk, from, target, flags)
                ),
              r != :ok,
              do: "#{move}: #{from}: #{inspect(elem(r, 1))}\n"

        {if(errs == [], do: 0, else: 1), "", Enum.join(errs), state}

      _ ->
        {2, "", "#{move}: needs a source and a destination\n", state}
    end
  end

  defp builtin("find", args, _stdin, state) do
    {roots, opts} = Enum.split_while(args, &(not String.starts_with?(&1, "-")))

    opts =
      opts
      |> Enum.chunk_every(2)
      |> Map.new(fn
        [k, v] -> {k, v}
        [k] -> {k, ""}
      end)

    name =
      opts["-name"] &&
        Regex.compile!(
          "^" <>
            (opts["-name"]
             |> Regex.escape()
             |> String.replace("\\*", ".*")
             |> String.replace("\\?", ".")) <> "$"
        )

    found =
      for root <- if(roots == [], do: ["."], else: roots),
          {path, dir} <- walk(state.disk, Disk.norm(root, state.cwd)),
          name == nil or Regex.match?(name, Path.basename(path)),
          opts["-type"] in [nil, if(dir, do: "d", else: "f")],
          do: shown(path, root, state) <> "\n"

    {0, Enum.join(found), "", state}
  end

  defp builtin("tree", args, _stdin, state) do
    root = Disk.norm(List.first(args) || ".", state.cwd)

    lines =
      for {path, dir} <- walk(state.disk, root),
          path != root,
          do:
            String.duplicate("  ", length(Path.split(Path.relative_to(path, root))) - 1) <>
              Path.basename(path) <> if(dir, do: "/", else: "")

    {0, Enum.map_join([root | lines], &(&1 <> "\n")), "", state}
  end

  # -- helpers -----------------------------------------------------------------------------------

  def flags(args) do
    {f, rest} = Enum.split_with(args, &(String.starts_with?(&1, "-") and &1 != "-"))
    {Enum.join(f), rest}
  end

  defp each(paths, state, fun) do
    {out, err} =
      Enum.reduce(paths, {"", ""}, fn p, {out, err} ->
        case fun.(Disk.norm(p, state.cwd)) do
          {:out, s} -> {out <> s, err}
          {:err, s} -> {out, err <> s}
          :ok -> {out, err}
        end
      end)

    {if(err == "", do: 0, else: 1), out, err, state}
  end

  defp done(:ok, _cmd, _path), do: :ok
  defp done({:error, e}, cmd, path), do: {:err, "#{cmd}: #{path}: #{e}\n"}

  defp entry(e, false), do: e.name <> if(e.dir, do: "/", else: "") <> "\n"

  defp entry(e, true) do
    when_ = e.mtime |> DateTime.from_unix!() |> Calendar.strftime("%b %d %H:%M")

    "#{if e.dir, do: "d", else: "-"} #{String.pad_leading(to_string(e.size), 9)} #{when_} #{e.name}#{if e.dir, do: "/", else: ""}\n"
  end

  defp walk(disk, path) do
    case Disk.stat(disk, path) do
      {:ok, %{dir: true}} ->
        {:ok, kids} = Disk.list(disk, path)
        [{path, true} | Enum.flat_map(kids, &walk(disk, Path.join(path, &1.name)))]

      {:ok, _} ->
        [{path, false}]

      _ ->
        []
    end
  end

  defp shown(path, root, state) do
    if String.starts_with?(root, "/"),
      do: path,
      else:
        Path.join(root, Path.relative_to(path, Disk.norm(root, state.cwd)))
        |> String.replace_suffix("/.", "")
  end

  defp copy(disk, from, to, flags) do
    case Disk.stat(disk, from) do
      {:ok, %{dir: true}} ->
        if String.contains?(flags, "r") or String.contains?(flags, "R") do
          for {path, dir} <- walk(disk, from) do
            target = Path.join(to, Path.relative_to(path, from))

            if dir,
              do: Disk.mkdir_p(disk, target),
              else: Disk.write(disk, target, elem(Disk.read(disk, path), 1))
          end

          :ok
        else
          {:error, :eisdir}
        end

      {:ok, _} ->
        with {:ok, data} <- Disk.read(disk, from), do: Disk.write(disk, to, data)

      error ->
        error
    end
  end
end

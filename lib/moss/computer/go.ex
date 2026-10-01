defmodule Moss.Computer.Go do
  @moduledoc """
  `go` on the computer (Arock's PROJECT.md §14): Go's own compiler and linker
  built for wasip1 (`go-compile.wasm`, `go-link.wasm`), driven here, since
  the `go` command would spawn them. The standard library is precompiled for
  wasip1/wasm in the shared `/usr/lib/go/pkg`, named by its `importcfg`; a
  program builds from the standard library alone (no modules are fetched).

      go build [-o out.wasm] [file.go ... | folder]   one main package to a .wasm
      go run [file.go ... | folder] [-- args]         built to /tmp, run, removed
      go version

  `run(args, ctx)`, `ctx` holding `exec.(argv0, args)`, `cwd`, `disk` and
  `start.(path, args)` that runs a built module.
  """
  alias Moss.Computer.Disk

  @version "go1.26.4"
  @cfg "/usr/lib/go/pkg/importcfg"

  def run(["version" | _], _ctx), do: {0, "go version #{@version} wasip1/wasm\n", ""}

  def run(["build" | args], ctx) do
    {out, rest} = output(args)

    with {:ok, files, name} <- sources(rest, ctx) do
      build(files, Disk.norm(out || name <> ".wasm", ctx.cwd), ctx)
    end
  end

  def run(["run" | args], ctx) do
    {srcs, given} = Enum.split_while(args, &(&1 != "--"))
    {srcs, given} = if given == [], do: split_run(srcs), else: {srcs, tl(given)}
    tmp = "/tmp/go-run-#{System.unique_integer([:positive])}.wasm"

    with {:ok, files, _} <- sources(srcs, ctx),
         {0, o1, e1} <- build(files, tmp, ctx) do
      {code, o2, e2} = ctx.start.(tmp, given)
      Disk.remove(ctx.disk, tmp)
      {code, o1 <> o2, e1 <> e2}
    end
  end

  def run(_, _ctx),
    do:
      {2, "",
       "go: on this computer: go build [-o out.wasm] [files | folder], go run, go version\n"}

  defp build(files, out, ctx) do
    archive = "/tmp/go-#{System.unique_integer([:positive])}.a"

    result =
      with {0, o1, e1} <-
             ctx.exec.(
               "go-compile",
               ["-o", archive, "-p", "main", "-complete", "-importcfg", @cfg, "-pack"] ++ files
             ),
           {0, o2, e2} <-
             ctx.exec.("go-link", ["-o", out, "-importcfg", @cfg, "-buildmode=exe", archive]) do
        {0, o1 <> o2, e1 <> e2}
      else
        # the compiler reports to stdout; for the agent these are errors
        {code, o, e} -> {code, "", o <> e <> hint(o <> e)}
      end

    Disk.remove(ctx.disk, archive)
    result
  end

  defp hint(said) do
    if said =~ "could not import",
      do: "go: this computer has Go's standard library only; modules are not fetched\n",
      else: ""
  end

  defp output(["-o", out | rest]), do: {out, rest}
  defp output(args), do: {nil, args}

  # go run's sources run up to the first argument that is not one
  defp split_run(args),
    do: Enum.split_while(args, &(String.ends_with?(&1, ".go") or &1 in [".", "./"]))

  defp sources(args, ctx) do
    case args do
      [] ->
        folder(ctx.cwd, ctx)

      [one] ->
        if String.ends_with?(one, ".go"),
          do: files([one], ctx),
          else: folder(Disk.norm(one, ctx.cwd), ctx)

      many ->
        files(many, ctx)
    end
  end

  defp files(names, ctx) do
    paths = Enum.map(names, &Disk.norm(&1, ctx.cwd))

    case Enum.find(paths, &match?({:error, _}, Disk.stat(ctx.disk, &1))) do
      nil -> {:ok, paths, paths |> hd() |> Path.basename(".go")}
      missing -> {1, "", "go: #{missing}: no such file\n"}
    end
  end

  defp folder(dir, ctx) do
    case Disk.list(ctx.disk, dir) do
      {:ok, kids} ->
        case for(
               k <- kids,
               not k.dir,
               String.ends_with?(k.name, ".go"),
               not String.ends_with?(k.name, "_test.go"),
               do: Path.join(dir, k.name)
             ) do
          [] -> {1, "", "go: no Go files in #{dir}\n"}
          paths -> {:ok, Enum.sort(paths), Path.basename(dir)}
        end

      _ ->
        {1, "", "go: #{dir}: no such folder\n"}
    end
  end
end

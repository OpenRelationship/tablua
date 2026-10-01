defmodule VolvoxServer.Computer.Clang do
  @moduledoc """
  Clang's driver, run the way the computer can (Volvox PROJECT.md §14): the
  YoWASP build (`clang.wasm`, one module that is `clang`, `clang++` and
  `wasm-ld` by its first argument) cannot spawn its compile and link steps,
  so the host asks it for them (`-###`) and runs each, in order, with the same
  module. The sysroot and clang's own headers are the shared
  `/usr/share/wasi-sysroot`; the output runs on the same computer.

  `run(argv0, args, exec, remove)` with `exec.(argv0, args) -> {code, out, err}`;
  `remove.(paths)` deletes the steps' files in `/tmp` afterwards, as the
  driver would have.
  """

  @sysroot "/usr/share/wasi-sysroot"

  # a call that does not compile, or is itself one of the steps, runs as given
  @direct ~w(-### -cc1 -cc1as --version -v -E -fsyntax-only --help -print-search-dirs)

  def run(argv0, args, exec, remove) do
    args = sysroot(args) |> exceptions(argv0)

    if Enum.any?(args, &(&1 in @direct)) do
      exec.(argv0, args)
    else
      case exec.(argv0, args ++ ["-###"]) do
        {0, _out, plan} ->
          jobs = jobs(plan)
          result = steps(jobs, argv0, exec, {0, "", ""})
          remove.(for(job <- jobs, a <- job, String.starts_with?(a, "/tmp/"), uniq: true, do: a))
          result

        failed ->
          failed
      end
    end
  end

  defp sysroot(args) do
    given = Enum.any?(args, &String.starts_with?(&1, "--sysroot"))
    if given, do: args, else: ["--sysroot=#{@sysroot}", "-resource-dir=#{@sysroot}" | args]
  end

  # the sysroot's C++ runtime has no unwinder: C++ is built without exceptions unless the program asks
  defp exceptions(args, "clang++") do
    if Enum.any?(args, &(&1 in ["-fexceptions", "-fwasm-exceptions", "-fno-exceptions"])),
      do: args,
      else: args ++ ["-fno-exceptions"]
  end

  defp exceptions(args, _), do: args

  defp steps([], _argv0, _exec, acc), do: acc

  defp steps([[tool | args] | rest], argv0, exec, {_, out, err}) do
    # the link step names wasm-ld; every other step is the driver's own -cc1
    as = if Path.basename(tool) == "wasm-ld", do: "wasm-ld", else: argv0

    case exec.(as, args) do
      {0, o, e} -> steps(rest, argv0, exec, {0, out <> o, err <> e})
      {code, o, e} -> {code, out <> o, err <> e}
    end
  end

  @doc "The steps `-###` printed: each a line of double-quoted arguments."
  def jobs(plan) do
    for line <- String.split(plan, "\n"),
        String.starts_with?(line, " \""),
        do:
          Regex.scan(~r/"((?:[^"\\]|\\.)*)"/, line, capture: :all_but_first)
          |> Enum.map(fn [a] -> Regex.replace(~r/\\(.)/, a, "\\1") end)
          # YoWASP's driver prints an empty program before the step's own name
          |> then(fn
            ["" | job] -> job
            job -> job
          end)
  end
end

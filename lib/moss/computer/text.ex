defmodule Moss.Computer.Text do
  @moduledoc """
  The shell's text tools over the computer's disk: `grep`, `head`, `tail`,
  `wc`, `sort`, `uniq`, `cut`, `tr`, `tee`, `seq`, `base64`, `sha256sum`.
  `run(name, args, stdin, state)` gives back `{code, out, err}`; with no file
  named, a tool reads stdin.
  """
  alias Moss.Computer.{Commands, Disk}

  @names ~w(grep head tail wc sort uniq cut tr tee seq base64 sha256sum)
  def names, do: @names

  def run("grep", args, stdin, state) do
    {flags, rest} = Commands.flags(args)

    case rest do
      [pattern | files] ->
        re = Regex.compile!(pattern, if(String.contains?(flags, "i"), do: "i", else: ""))
        files = if String.contains?(flags, "r"), do: tree(files, state), else: files
        many = length(files) > 1 or String.contains?(flags, "r")

        hits =
          for {name, text} <- inputs(files, stdin, state),
              {line, n} <- Enum.with_index(lines(text), 1),
              Regex.match?(re, line) != String.contains?(flags, "v"),
              do: {name, n, line}

        out =
          cond do
            String.contains?(flags, "l") ->
              hits |> Enum.map(&elem(&1, 0)) |> Enum.uniq() |> Enum.map_join(&(&1 <> "\n"))

            String.contains?(flags, "c") ->
              "#{length(hits)}\n"

            true ->
              Enum.map_join(hits, fn {name, n, line} ->
                prefix(many, name) <>
                  if(String.contains?(flags, "n"), do: "#{n}:", else: "") <> line <> "\n"
              end)
          end

        {if(hits == [], do: 1, else: 0), out, ""}

      [] ->
        {2, "", "grep: needs a pattern\n"}
    end
  rescue
    e in Regex.CompileError -> {2, "", "grep: #{Exception.message(e)}\n"}
  end

  def run(edge, args, stdin, state) when edge in ["head", "tail"] do
    {n, files} = count(args, 10)

    out =
      Enum.map_join(inputs(files, stdin, state), fn {_name, text} ->
        ls = lines(text)
        picked = if edge == "head", do: Enum.take(ls, n), else: Enum.take(ls, -n)
        Enum.map_join(picked, &(&1 <> "\n"))
      end)

    {0, out, ""}
  end

  def run("wc", args, stdin, state) do
    {flags, files} = Commands.flags(args)
    pick = if flags == "", do: "lwc", else: flags

    out =
      Enum.map_join(inputs(files, stdin, state), fn {name, text} ->
        counts = [
          {"l", length(lines(text))},
          {"w", length(String.split(text))},
          {"c", byte_size(text)}
        ]

        nums =
          for {k, v} <- counts, String.contains?(pick, k), do: String.pad_leading(to_string(v), 7)

        Enum.join(nums) <> if(name == "-", do: "", else: " " <> name) <> "\n"
      end)

    {0, out, ""}
  end

  def run("sort", args, stdin, state) do
    {flags, files} = Commands.flags(args)
    ls = Enum.flat_map(inputs(files, stdin, state), fn {_, t} -> lines(t) end)
    ls = if String.contains?(flags, "n"), do: Enum.sort_by(ls, &number/1), else: Enum.sort(ls)
    ls = if String.contains?(flags, "r"), do: Enum.reverse(ls), else: ls
    ls = if String.contains?(flags, "u"), do: Enum.dedup(ls), else: ls
    {0, Enum.map_join(ls, &(&1 <> "\n")), ""}
  end

  def run("uniq", args, stdin, state) do
    {flags, files} = Commands.flags(args)

    runs =
      inputs(files, stdin, state)
      |> Enum.flat_map(fn {_, t} -> lines(t) end)
      |> Enum.chunk_by(& &1)

    out =
      Enum.map_join(runs, fn [l | _] = run ->
        if String.contains?(flags, "c"),
          do: String.pad_leading(to_string(length(run)), 7) <> " " <> l <> "\n",
          else: l <> "\n"
      end)

    {0, out, ""}
  end

  def run("cut", args, stdin, state) do
    {opts, files} = opts(args)
    delim = opts["-d"] || "\t"
    fields = (opts["-f"] || "1") |> String.split(",") |> Enum.map(&String.to_integer/1)

    out =
      inputs(files, stdin, state)
      |> Enum.flat_map(fn {_, t} -> lines(t) end)
      |> Enum.map_join(fn l ->
        parts = String.split(l, delim)
        (fields |> Enum.map(&Enum.at(parts, &1 - 1, "")) |> Enum.join(delim)) <> "\n"
      end)

    {0, out, ""}
  rescue
    _ -> {1, "", "cut: use -d <delimiter> -f <field,...>\n"}
  end

  def run("tr", [from, to], stdin, _state) do
    map =
      Enum.zip(
        String.graphemes(from),
        Stream.cycle(String.graphemes(to)) |> Enum.take(String.length(from))
      )
      |> Map.new()

    {0, stdin |> String.graphemes() |> Enum.map_join(&Map.get(map, &1, &1)), ""}
  end

  def run("tr", ["-d", gone], stdin, _state),
    do: {0, String.replace(stdin, String.graphemes(gone), ""), ""}

  def run("tr", _, _, _), do: {1, "", "tr: tr <from> <to>, or tr -d <chars>\n"}

  def run("tee", args, stdin, state) do
    {flags, files} = Commands.flags(args)

    for f <- files do
      path = Disk.norm(f, state.cwd)

      old =
        if String.contains?(flags, "a"),
          do: elem(Disk.read(state.disk, path), 1) |> then(&if(is_binary(&1), do: &1, else: "")),
          else: ""

      Disk.write(state.disk, path, old <> stdin)
    end

    {0, stdin, ""}
  end

  def run("seq", args, _stdin, _state) do
    nums = Enum.map(args, &String.to_integer/1)

    {first, step, last} =
      case nums do
        [l] -> {1, 1, l}
        [f, l] -> {f, 1, l}
        [f, s, l] -> {f, s, l}
      end

    {0,
     first
     |> Stream.iterate(&(&1 + step))
     |> Enum.take_while(&if(step > 0, do: &1 <= last, else: &1 >= last))
     |> Enum.map_join(&"#{&1}\n"), ""}
  rescue
    _ -> {1, "", "seq: seq [first [step]] last\n"}
  end

  def run("base64", args, stdin, state) do
    {flags, files} = Commands.flags(args)
    text = inputs(files, stdin, state) |> Enum.map_join(&elem(&1, 1))

    if String.contains?(flags, "d") do
      case Base.decode64(String.replace(text, ~r/\s/, "")) do
        {:ok, bytes} -> {0, bytes, ""}
        :error -> {1, "", "base64: not base64\n"}
      end
    else
      {0, Base.encode64(text) <> "\n", ""}
    end
  end

  def run("sha256sum", files, stdin, state) do
    out =
      Enum.map_join(inputs(files, stdin, state), fn {name, t} ->
        Base.encode16(:crypto.hash(:sha256, t), case: :lower) <> "  " <> name <> "\n"
      end)

    {0, out, ""}
  end

  # -- helpers -----------------------------------------------------------------------------------

  defp inputs([], stdin, _state), do: [{"-", stdin}]

  defp inputs(files, _stdin, state) do
    for f <- files, {:ok, text} <- [Disk.read(state.disk, Disk.norm(f, state.cwd))], do: {f, text}
  end

  defp tree(files, state) do
    for root <- if(files == [], do: ["."], else: files),
        path <- walk(state.disk, Disk.norm(root, state.cwd)),
        do: path
  end

  defp walk(disk, path) do
    case Disk.list(disk, path) do
      {:ok, kids} -> Enum.flat_map(kids, &walk(disk, Path.join(path, &1.name)))
      {:error, :enotdir} -> [path]
      _ -> []
    end
  end

  defp lines(""), do: []
  defp lines(text), do: text |> String.trim_trailing("\n") |> String.split("\n")
  defp prefix(true, name), do: name <> ":"
  defp prefix(false, _), do: ""

  defp count(["-n", n | rest], _), do: {String.to_integer(n), rest}

  defp count(["-" <> n | rest], d),
    do: if(n =~ ~r/^\d+$/, do: {String.to_integer(n), rest}, else: {d, rest})

  defp count(rest, d), do: {d, rest}

  defp opts(args) do
    {pairs, files} =
      Enum.reduce(args, {%{}, [], nil}, fn
        a, {o, f, nil} when a in ["-d", "-f"] -> {o, f, a}
        "-d" <> d, {o, f, nil} -> {Map.put(o, "-d", d), f, nil}
        "-f" <> v, {o, f, nil} -> {Map.put(o, "-f", v), f, nil}
        a, {o, f, nil} -> {o, [a | f], nil}
        a, {o, f, k} -> {Map.put(o, k, a), f, nil}
      end)
      |> then(fn {o, f, _} -> {o, Enum.reverse(f)} end)

    {pairs, files}
  end

  defp number(l),
    do:
      case(Float.parse(String.trim(l)),
        do: (
          {n, _} -> n
          :error -> 0.0
        )
      )
end

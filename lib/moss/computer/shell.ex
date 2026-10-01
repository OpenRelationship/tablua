defmodule Moss.Computer.Shell do
  @moduledoc """
  The computer's shell: a line of commands run in the computer's own process,
  as sh would run it, without fork. `run(line, state)` gives back
  `{%{out, err, code}, state}`; `state` carries the disk, the working folder
  and the variables, and what a command changes in it (`cd`, `export`) lasts.

  It reads: words with '…' and "…" quoting and `\\` escapes, `$VAR` and `${VAR}`
  (not inside '…'), `~`, `*` and `?` in the last part of a path, pipes `|`,
  redirects `>`, `>>`, `<`, `2>`, `2>&1`, and `&&`, `||`, `;` between pipelines.
  The commands are `Computer.Commands`.
  """
  alias Moss.Computer.{Commands, Disk}

  def run(line, state) do
    case parse(line) do
      {:ok, chain} -> chain(chain, state, %{out: "", err: "", code: 0})
      {:error, why} -> {%{out: "", err: "sh: #{why}\n", code: 2}, state}
    end
  end

  # -- running -----------------------------------------------------------------------------------

  defp chain([], state, acc), do: {acc, state}

  defp chain([{op, pipeline} | rest], state, acc) do
    go =
      op == :first or op == :then or (op == :and and acc.code == 0) or
        (op == :or and acc.code != 0)

    if go do
      {r, state} = pipeline(pipeline, state)
      state = %{state | last_code: r.code}
      chain(rest, state, %{out: acc.out <> r.out, err: acc.err <> r.err, code: r.code})
    else
      chain(rest, state, acc)
    end
  end

  defp pipeline(cmds, state) do
    {r, state} =
      Enum.reduce(cmds, {%{out: "", err: "", code: 0}, state}, fn cmd, {prev, state} ->
        {r, state} = command(cmd, prev.out, state)
        {%{r | err: prev.err <> r.err}, state}
      end)

    {r, state}
  end

  defp command(%{words: words, redirects: redirects}, stdin, state) do
    argv = Enum.flat_map(words, &expand(&1, state))

    with {:ok, stdin} <- input(redirects, stdin, state) do
      {code, out, err, state} =
        if argv == [], do: {0, "", "", state}, else: Commands.run(argv, stdin, state)

      output(redirects, %{out: out, err: err, code: code}, state)
    else
      {:error, why} -> {%{out: "", err: "sh: #{why}\n", code: 1}, state}
    end
  end

  defp input(redirects, stdin, state) do
    case Enum.find(redirects, &match?({:in, _}, &1)) do
      {:in, word} ->
        path = word |> expand_one(state) |> Disk.norm(state.cwd)

        case Disk.read(state.disk, path) do
          {:ok, data} -> {:ok, data}
          {:error, _} -> {:error, "#{path}: no such file"}
        end

      nil ->
        {:ok, stdin}
    end
  end

  defp output(redirects, r, state) do
    Enum.reduce(redirects, {r, state}, fn
      {:err_to_out}, {r, state} ->
        {%{r | out: r.out <> r.err, err: ""}, state}

      {kind, word}, {r, state} when kind in [:out, :append, :err_out] ->
        path = word |> expand_one(state) |> Disk.norm(state.cwd)

        {bytes, r} =
          if kind == :err_out, do: {r.err, %{r | err: ""}}, else: {r.out, %{r | out: ""}}

        old =
          if kind == :append,
            do:
              elem(Disk.read(state.disk, path), 1) |> then(&if(is_binary(&1), do: &1, else: "")),
            else: ""

        case Disk.write(state.disk, path, old <> bytes) do
          :ok -> {r, state}
          {:error, e} -> {%{r | err: r.err <> "sh: #{path}: #{e}\n", code: 1}, state}
        end

      _, acc ->
        acc
    end)
  end

  # -- expanding ---------------------------------------------------------------------------------

  defp expand_one(word, state), do: word |> expand(state) |> List.first("")

  # a word is a list of {quoted?, text} parts; variables are expanded unless single-quoted, globs only unquoted
  defp expand(parts, state) do
    text =
      Enum.map_join(parts, fn
        {:single, s} -> s
        {_, s} -> vars(s, state)
      end)

    text =
      if match?([{:bare, "~" <> _} | _], parts),
        do: String.replace_prefix(text, "~", state.env["HOME"] || "/"),
        else: text

    globbed = Enum.any?(parts, fn {q, s} -> q == :bare and String.contains?(s, ["*", "?"]) end)
    if globbed, do: glob(text, state), else: [text]
  end

  defp vars(s, state) do
    Regex.replace(~r/\$(\{(\w+)\}|(\w+)|\?)/, s, fn
      "$?", _, _, _ -> to_string(state.last_code)
      _, _, "", name -> Map.get(state.env, name, "")
      _, _, name, _ -> Map.get(state.env, name, "")
    end)
  end

  defp glob(pattern, state) do
    full = Disk.norm(pattern, state.cwd)
    {dir, base} = {Path.dirname(full), Path.basename(full)}

    re =
      Regex.compile!(
        "^" <>
          (base |> Regex.escape() |> String.replace("\\*", ".*") |> String.replace("\\?", ".")) <>
          "$"
      )

    matches =
      case Disk.list(state.disk, dir) do
        {:ok, kids} ->
          for k <- kids,
              Regex.match?(re, k.name),
              not String.starts_with?(k.name, "."),
              do: Path.join(Path.dirname(pattern), k.name)

        _ ->
          []
      end

    if matches == [], do: [pattern], else: Enum.map(matches, &String.replace_prefix(&1, "./", ""))
  end

  # -- parsing -----------------------------------------------------------------------------------

  @doc "A line as `[{op, [%{words, redirects}]}]`, op one of :first, :and, :or, :then."
  def parse(line) do
    with {:ok, tokens} <- tokens(String.to_charlist(line), [], [], nil) do
      tokens
      |> Enum.chunk_by(&(&1 in [:and, :or, :then]))
      |> build(:first, [])
    end
  end

  defp build([], _op, acc), do: {:ok, Enum.reverse(acc)}

  defp build([[op] | rest], _prev, acc) when op in [:and, :or, :then], do: build(rest, op, acc)

  defp build([tokens | rest], op, acc) do
    cmds =
      tokens
      |> Enum.chunk_by(&(&1 == :pipe))
      |> Enum.reject(&(&1 == [:pipe]))
      |> Enum.map(&cmd(&1, %{words: [], redirects: []}))

    if Enum.any?(cmds, &(&1 == :error)),
      do: {:error, "a redirect names no file"},
      else: build(rest, op, [{op, cmds} | acc])
  end

  defp cmd([], c), do: %{c | words: Enum.reverse(c.words), redirects: Enum.reverse(c.redirects)}

  defp cmd([:err_to_out | rest], c),
    do: cmd(rest, %{c | redirects: [{:err_to_out} | c.redirects]})

  defp cmd([r, {:word, w} | rest], c) when r in [:out, :append, :in, :err_out],
    do: cmd(rest, %{c | redirects: [{r, w} | c.redirects]})

  defp cmd([r | _], _c) when r in [:out, :append, :in, :err_out], do: :error
  defp cmd([{:word, w} | rest], c), do: cmd(rest, %{c | words: [w | c.words]})

  # tokens: {:word, parts} and operators; `word` gathers the parts of the word being read
  defp tokens([], acc, word, nil), do: {:ok, Enum.reverse(flush(acc, word))}
  defp tokens([], _acc, _word, _quote), do: {:error, "a quote is not closed"}

  defp tokens([?' | rest], acc, word, nil) do
    case Enum.split_while(rest, &(&1 != ?')) do
      {s, [?' | rest]} -> tokens(rest, acc, [{:single, to_string(s)} | word], nil)
      _ -> {:error, "a quote is not closed"}
    end
  end

  defp tokens([?" | rest], acc, word, nil) do
    case double(rest, []) do
      {:ok, s, rest} -> tokens(rest, acc, [{:double, s} | word], nil)
      :error -> {:error, "a quote is not closed"}
    end
  end

  defp tokens([?\\, ch | rest], acc, word, nil),
    do: tokens(rest, acc, [{:single, <<ch::utf8>>} | word], nil)

  defp tokens([?2, ?>, ?&, ?1 | rest], acc, [], nil),
    do: tokens(rest, [:err_to_out | acc], [], nil)

  defp tokens([?2, ?> | rest], acc, [], nil), do: tokens(rest, [:err_out | acc], [], nil)

  defp tokens([?&, ?& | rest], acc, word, nil),
    do: tokens(rest, [:and | flush(acc, word)], [], nil)

  defp tokens([?|, ?| | rest], acc, word, nil),
    do: tokens(rest, [:or | flush(acc, word)], [], nil)

  defp tokens([?>, ?> | rest], acc, word, nil),
    do: tokens(rest, [:append | flush(acc, word)], [], nil)

  defp tokens([?| | rest], acc, word, nil), do: tokens(rest, [:pipe | flush(acc, word)], [], nil)
  defp tokens([?> | rest], acc, word, nil), do: tokens(rest, [:out | flush(acc, word)], [], nil)
  defp tokens([?< | rest], acc, word, nil), do: tokens(rest, [:in | flush(acc, word)], [], nil)
  defp tokens([?; | rest], acc, word, nil), do: tokens(rest, [:then | flush(acc, word)], [], nil)
  defp tokens([?\n | rest], acc, word, nil), do: tokens(rest, [:then | flush(acc, word)], [], nil)

  defp tokens([ch | rest], acc, word, nil) when ch in [?\s, ?\t],
    do: tokens(rest, flush(acc, word), [], nil)

  defp tokens([ch | rest], acc, [{:bare, s} | word], nil),
    do: tokens(rest, acc, [{:bare, s <> <<ch::utf8>>} | word], nil)

  defp tokens([ch | rest], acc, word, nil),
    do: tokens(rest, acc, [{:bare, <<ch::utf8>>} | word], nil)

  defp double([?" | rest], s), do: {:ok, s |> Enum.reverse() |> to_string(), rest}
  defp double([?\\, ch | rest], s) when ch in [?", ?\\, ?$], do: double(rest, [ch | s])
  defp double([ch | rest], s), do: double(rest, [ch | s])
  defp double([], _s), do: :error

  defp flush(acc, []), do: acc
  defp flush(acc, word), do: [{:word, Enum.reverse(word)} | acc]
end

defmodule MossBrowser.HTMLTokenizerTest do
  # MossBrowser.HTML's tokenizer against html5lib-tests (tokenizer/*.test at 0b8d24c, 2023, MIT, licence in
  # test/fixtures/html5lib). Parse errors are not compared, and a doctype is compared by its name only: the
  # tokenizer keeps no public or system identifier, since nothing in moss-browser reads them. Cases that start in the
  # CDATA section state, or whose input holds a lone surrogate (not UTF-8, so never a page moss-browser reads), are left out.
  use ExUnit.Case, async: true

  alias MossBrowser.HTML.Tokenizer

  @dir "test/fixtures/html5lib"
  @states %{
    "Data state" => :data,
    "PLAINTEXT state" => :plaintext,
    "RCDATA state" => :rcdata,
    "RAWTEXT state" => :rawtext,
    "Script data state" => :script
  }

  @cases for file <- Path.wildcard(@dir <> "/*.test"),
             t <- Map.get(Jason.decode!(File.read!(file)), "tests", []),
             state <- Map.get(t, "initialStates", ["Data state"]),
             do: {Path.basename(file), state, t}

  defp unescape(s, true) when is_binary(s) do
    Regex.replace(~r/\\u([0-9A-Fa-f]{4})/, s, fn _, hex ->
      case String.to_integer(hex, 16) do
        c when c in 0xD800..0xDFFF -> throw(:surrogate)
        c -> <<c::utf8>>
      end
    end)
  end

  defp unescape(s, _), do: s

  defp tokens(input, mode, last),
    do:
      Stream.unfold({Tokenizer.prepare(input), Tokenizer.new(mode, last)}, &step/1)
      |> Enum.to_list()

  defp step({rest, ts}) do
    case Tokenizer.next(rest, ts) do
      :eof -> nil
      {tok, rest, ts} -> {tok, {rest, ts}}
    end
  end

  defp ours(toks) do
    toks
    |> Enum.map(fn
      {:start, n, a, sc} -> ["StartTag", n, Map.new(a)] ++ if(sc, do: [true], else: [])
      {:end, n} -> ["EndTag", n]
      {:text, t} -> ["Character", t]
      {:comment, c} -> ["Comment", c]
      {:doctype, n} -> ["DOCTYPE", n]
    end)
    |> merge()
  end

  defp theirs(out, esc) do
    out
    |> Enum.map(fn
      ["DOCTYPE", n | _] ->
        ["DOCTYPE", n || ""]

      ["StartTag", n, a] ->
        ["StartTag", n, Map.new(a, fn {k, v} -> {unescape(k, esc), unescape(v, esc)} end)]

      ["StartTag", n, a, true] ->
        ["StartTag", n, Map.new(a, fn {k, v} -> {unescape(k, esc), unescape(v, esc)} end), true]

      [kind, d] when kind in ["Character", "Comment"] ->
        [kind, unescape(d, esc)]

      other ->
        other
    end)
    |> merge()
  end

  defp merge([["Character", a], ["Character", b] | rest]),
    do: merge([["Character", a <> b] | rest])

  defp merge([t | rest]), do: [t | merge(rest)]
  defp merge([]), do: []

  test "html5lib's tokenizer tests pass" do
    results =
      for {file, state, t} <- @cases, mode = @states[state], mode != nil do
        esc = t["doubleEscaped"] == true

        try do
          input = unescape(t["input"], esc)
          expected = theirs(t["output"], esc)
          got = input |> tokens(mode, t["lastStartTag"]) |> ours()

          if got == expected,
            do: :pass,
            else:
              {:fail,
               "#{file} #{state}: #{t["description"]}\n  #{inspect(expected)}\n  #{inspect(got)}"}
        catch
          :surrogate -> :skip
        end
      end

    fails = for {:fail, msg} <- results, do: msg
    passed = Enum.count(results, &(&1 == :pass))

    IO.puts(
      "\n  html5lib tokenizer: #{passed} passed, #{length(fails)} failed, #{Enum.count(results, &(&1 == :skip))} left out"
    )

    assert fails == [], Enum.join(Enum.take(fails, 30), "\n")
    assert passed > 2500
  end
end

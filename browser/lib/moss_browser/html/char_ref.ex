defmodule MossBrowser.HTML.CharRef do
  @moduledoc """
  Character references as the HTML standard's tokenizer reads them (§13.2.5.72 on): `&name;`, the legacy names
  that need no semicolon, `&#123;` and `&#x7b;`. `decode/2` takes the text after an `&` and gives back
  `{replacement, rest}`; when nothing matches the `&` stands for itself.

  The table of names is the standard's own (`priv/html/entities.txt`), read when moss-browser is compiled.
  """

  @table_file Path.expand("../../../priv/html/entities.txt", __DIR__)
  @external_resource @table_file

  @table @table_file
         |> File.read!()
         |> String.split("\n", trim: true)
         |> Enum.reject(&String.starts_with?(&1, "#"))
         |> Map.new(fn line ->
           [name | points] = String.split(line, " ")
           {name, for(p <- points, into: "", do: <<String.to_integer(p, 16)::utf8>>)}
         end)

  # the longest name is "CounterClockwiseContourIntegral;", 33 bytes
  @longest 32

  # what a numeric reference to a C1 control means: the windows-1252 character a page meant (§13.2.5.80)
  @c1 %{
    0x80 => 0x20AC,
    0x82 => 0x201A,
    0x83 => 0x0192,
    0x84 => 0x201E,
    0x85 => 0x2026,
    0x86 => 0x2020,
    0x87 => 0x2021,
    0x88 => 0x02C6,
    0x89 => 0x2030,
    0x8A => 0x0160,
    0x8B => 0x2039,
    0x8C => 0x0152,
    0x8E => 0x017D,
    0x91 => 0x2018,
    0x92 => 0x2019,
    0x93 => 0x201C,
    0x94 => 0x201D,
    0x95 => 0x2022,
    0x96 => 0x2013,
    0x97 => 0x2014,
    0x98 => 0x02DC,
    0x99 => 0x2122,
    0x9A => 0x0161,
    0x9B => 0x203A,
    0x9C => 0x0153,
    0x9E => 0x017E,
    0x9F => 0x0178
  }

  @doc """
  The reference at the start of `rest` (the text just after an `&`): `{text, rest}`. In an attribute's value
  (`attr?` true) a name without its semicolon followed by `=` or a letter or digit is left as written, as
  browsers do, so `?a=1&copy=2` keeps its `&copy`.
  """
  def decode(<<?#, x, rest::binary>>, _attr?) when x in [?x, ?X] do
    case hex(rest, 0, 0) do
      {0, _, _} -> {"&#" <> <<x>>, rest}
      {_, n, rest} -> {code(n), semi(rest)}
    end
  end

  def decode(<<?#, rest::binary>>, _attr?) do
    case dec(rest, 0, 0) do
      {0, _, _} -> {"&#", rest}
      {_, n, rest} -> {code(n), semi(rest)}
    end
  end

  def decode(rest, attr?) do
    run = alnum(rest, 0)

    if run == 0 do
      {"&", rest}
    else
      named(rest, min(run, @longest), run, attr?)
    end
  end

  defp named(rest, 0, _run, _attr?), do: {"&", rest}

  defp named(rest, len, run, attr?) do
    name = binary_part(rest, 0, len)
    after_name = binary_part(rest, len, byte_size(rest) - len)

    cond do
      len == run and match?(<<?;, _::binary>>, after_name) and Map.has_key?(@table, name <> ";") ->
        <<?;, after_semi::binary>> = after_name
        {Map.fetch!(@table, name <> ";"), after_semi}

      Map.has_key?(@table, name) ->
        if attr? and continues?(after_name),
          do: {"&", rest},
          else: {Map.fetch!(@table, name), after_name}

      true ->
        named(rest, len - 1, run, attr?)
    end
  end

  defp continues?(<<c, _::binary>>), do: c == ?= or alnum?(c)
  defp continues?(<<>>), do: false

  defp alnum(<<c, rest::binary>>, n) when n < 64,
    do: if(alnum?(c), do: alnum(rest, n + 1), else: n)

  defp alnum(_, n), do: n

  defp alnum?(c), do: c in ?a..?z or c in ?A..?Z or c in ?0..?9

  # digits read: {how many, value (held at 0x110000 once past the last code point), rest}
  defp hex(<<c, rest::binary>>, k, n) when c in ?0..?9, do: hex(rest, k + 1, cap(n * 16 + c - ?0))

  defp hex(<<c, rest::binary>>, k, n) when c in ?a..?f,
    do: hex(rest, k + 1, cap(n * 16 + c - ?a + 10))

  defp hex(<<c, rest::binary>>, k, n) when c in ?A..?F,
    do: hex(rest, k + 1, cap(n * 16 + c - ?A + 10))

  defp hex(rest, k, n), do: {k, n, rest}

  defp dec(<<c, rest::binary>>, k, n) when c in ?0..?9, do: dec(rest, k + 1, cap(n * 10 + c - ?0))
  defp dec(rest, k, n), do: {k, n, rest}

  defp cap(n), do: min(n, 0x110000)

  defp semi(<<?;, rest::binary>>), do: rest
  defp semi(rest), do: rest

  defp code(0), do: "�"
  defp code(n) when n > 0x10FFFF, do: "�"
  defp code(n) when n in 0xD800..0xDFFF, do: "�"
  defp code(n) when is_map_key(@c1, n), do: <<Map.fetch!(@c1, n)::utf8>>
  defp code(n), do: <<n::utf8>>
end

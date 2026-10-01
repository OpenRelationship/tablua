defmodule Moss.Sql.Lexer do
  @moduledoc """
  The agent's SQL as tokens, by SQLite's lexical rules: `'text'` with `''`
  inside, identifiers bare or quoted with `"`, `[]` or backticks, numbers
  (hex `0x` included), `x'..'` blobs, the parameters `?`, `?N`, `:name`,
  `@name` and `$name`, and `--` and `/* */` comments.

  A token is `{kind, value, from, to}` (`to` exclusive, byte offsets into
  the SQL, which a result column's name is cut from): `:word` (value the
  upper-cased word, the original kept as `{upper, original}`), `:id` (a
  quoted identifier), `:str`, `:num`, `:blob`, `:param`, `:op` and `:semi`.
  """

  @ops [
    "||",
    "<<",
    ">>",
    "<=",
    ">=",
    "==",
    "!=",
    "<>",
    "->",
    "(",
    ")",
    ",",
    ".",
    "+",
    "-",
    "*",
    "/",
    "%",
    "<",
    ">",
    "=",
    "&",
    "|",
    "~"
  ]

  def tokens(sql), do: lex(sql, 0, [])

  defp lex(sql, i, acc) do
    case sql do
      <<_::binary-size(^i)>> ->
        {:ok, Enum.reverse(acc)}

      <<_::binary-size(^i), rest::binary>> ->
        case token(rest, i, sql) do
          {:skip, n} -> lex(sql, i + n, acc)
          {:ok, tok, n} -> lex(sql, i + n, [tok | acc])
          {:error, _} = e -> e
        end
    end
  end

  defp token(<<c, _::binary>>, _i, _sql) when c in [?\s, ?\t, ?\n, ?\r, ?\f], do: {:skip, 1}

  defp token("--" <> rest, _i, _sql) do
    case :binary.match(rest, "\n") do
      {at, _} -> {:skip, at + 3}
      :nomatch -> {:skip, byte_size(rest) + 2}
    end
  end

  defp token("/*" <> rest, _i, _sql) do
    case :binary.match(rest, "*/") do
      {at, _} -> {:skip, at + 4}
      :nomatch -> {:skip, byte_size(rest) + 2}
    end
  end

  defp token(";" <> _, i, _), do: {:ok, {:semi, ";", i, i + 1}, 1}

  defp token(<<q, rest::binary>> = all, i, _) when q in [?', ?", ?`] do
    case quoted(rest, q, "") do
      {:ok, s, n} ->
        kind = if q == ?', do: :str, else: :id
        {:ok, {kind, s, i, i + n + 1}, n + 1}

      :error ->
        unrecognized(all)
    end
  end

  defp token("[" <> rest = all, i, _) do
    case :binary.match(rest, "]") do
      {at, _} -> {:ok, {:id, binary_part(rest, 0, at), i, i + at + 2}, at + 2}
      :nomatch -> unrecognized(all)
    end
  end

  defp token(<<x, ?', rest::binary>> = all, i, _) when x in [?x, ?X] do
    case :binary.match(rest, "'") do
      {at, _} ->
        hex = binary_part(rest, 0, at)

        if rem(byte_size(hex), 2) == 0 and Regex.match?(~r/\A[0-9a-fA-F]*\z/, hex),
          do: {:ok, {:blob, {:blob, Base.decode16!(hex, case: :mixed)}, i, i + at + 3}, at + 3},
          else: unrecognized(binary_part(all, 0, at + 3))

      :nomatch ->
        unrecognized(all)
    end
  end

  defp token(<<c, _::binary>> = s, i, _) when c in ?0..?9 or c == ?. do
    case Regex.run(~r/\A(0[xX][0-9a-fA-F]+|(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?)/, s) do
      [m | _] ->
        if Regex.match?(
             ~r/\A[A-Za-z_]/,
             binary_part(s, byte_size(m), byte_size(s) - byte_size(m))
           ) do
          unrecognized(hd(Regex.run(~r/\A[0-9A-Za-z_.]+/, s)))
        else
          {:ok, {:num, number(m), i, i + byte_size(m)}, byte_size(m)}
        end

      nil ->
        {:ok, {:op, ".", i, i + 1}, 1}
    end
  end

  defp token("?" <> rest, i, _) do
    case Regex.run(~r/\A\d+/, rest) do
      [d] ->
        {:ok, {:param, {:n, String.to_integer(d)}, i, i + 1 + byte_size(d)}, 1 + byte_size(d)}

      nil ->
        {:ok, {:param, :next, i, i + 1}, 1}
    end
  end

  defp token(<<c, rest::binary>> = all, i, _) when c in [?:, ?@, ?$] do
    case Regex.run(~r/\A[A-Za-z0-9_]+/, rest) do
      [n] -> {:ok, {:param, {:name, <<c>> <> n}, i, i + 1 + byte_size(n)}, 1 + byte_size(n)}
      nil -> unrecognized(binary_part(all, 0, 1))
    end
  end

  defp token(<<c, _::binary>> = s, i, _) when c in ?a..?z or c in ?A..?Z or c == ?_ or c >= 128 do
    [w] = Regex.run(~r/\A[A-Za-z0-9_$\x{80}-\x{10FFFF}]+/u, s) || [binary_part(s, 0, 1)]
    {:ok, {:word, {String.upcase(w), w}, i, i + byte_size(w)}, byte_size(w)}
  end

  defp token(s, i, _) do
    case Enum.find(@ops, &String.starts_with?(s, &1)) do
      nil -> unrecognized(binary_part(s, 0, 1))
      op -> {:ok, {:op, normal(op), i, i + byte_size(op)}, byte_size(op)}
    end
  end

  defp normal("=="), do: "="
  defp normal("<>"), do: "!="
  defp normal(op), do: op

  defp quoted(s, q, acc) do
    case :binary.match(s, <<q>>) do
      :nomatch ->
        :error

      {at, _} ->
        part = binary_part(s, 0, at)
        rest = binary_part(s, at + 1, byte_size(s) - at - 1)

        case rest do
          <<^q, more::binary>> ->
            case quoted(more, q, acc <> part <> <<q>>) do
              {:ok, v, n} -> {:ok, v, n + at + 2}
              e -> e
            end

          _ ->
            {:ok, acc <> part, at + 1}
        end
    end
  end

  defp number("0x" <> h), do: hex(h)
  defp number("0X" <> h), do: hex(h)

  defp number(m) do
    if Regex.match?(~r/\A\d+\z/, m) do
      n = String.to_integer(m)
      if n > Moss.Sql.Value.max_int(), do: n * 1.0, else: n
    else
      Moss.Sql.Value.parse_number(m)
    end
  end

  # SQLite reads hex as a 64-bit two's complement integer
  defp hex(h) do
    n = String.to_integer(h, 16)
    if n >= 0x8000000000000000, do: n - 0x10000000000000000, else: n
  end

  defp unrecognized(s), do: {:error, ~s(unrecognized token: "#{s}")}
end

defmodule Moss.Log.Tokens do
  @moduledoc """
  alog's tokenizer (`tokens.lua`), again in Elixir for the hot path: the
  words recall indexes a text by and searches a query by. It is held to alog's
  `tokens_vectors.lua`, read by the test at run time.

    1. The text is bytes. A word byte is 0-9, A-Z, a-z or any byte from 0x80
       to 0xFF; every other byte separates words.
    2. The tokens are the maximal runs of word bytes, in the order they occur.
    3. Each byte A-Z becomes its lower case; no other byte changes.
    4. A token keeps its first 64 bytes, even if that splits a UTF-8 character.
    5. Only the first 10,000 tokens are kept; the rest of the text is not read.
  """

  @token_bytes 64
  @max 10_000

  defguardp word?(c) when c in ?0..?9 or c in ?a..?z or c in ?A..?Z or c >= 0x80

  @doc "alog's TOKEN_BYTES and TOKENS: a token's most bytes, a text's most tokens."
  def limits, do: {@token_bytes, @max}

  @doc "The tokens of `text`, in order."
  def tokens(text) when is_binary(text), do: text |> skip(text, 0, [], 0) |> Enum.reverse()

  @doc """
  A document as recall indexes it: its distinct terms, each with its count
  (`[{term, tf}]`, in no particular order: the index keys them), and its length
  in tokens.
  """
  def count(list) when is_list(list),
    do: {list |> Enum.frequencies() |> Map.to_list(), length(list)}

  # between words: i is the offset of the next byte
  defp skip(<<c, rest::binary>>, text, i, acc, n) when word?(c),
    do: word(rest, text, i, i + 1, c in ?A..?Z, acc, n)

  defp skip(<<_, rest::binary>>, text, i, acc, n), do: skip(rest, text, i + 1, acc, n)
  defp skip(<<>>, _text, _i, acc, _n), do: acc

  # in a word that began at s
  defp word(<<c, rest::binary>>, text, s, i, up, acc, n) when word?(c),
    do: word(rest, text, s, i + 1, up or c in ?A..?Z, acc, n)

  defp word(rest, text, s, i, up, acc, n) do
    acc = [cut(text, s, i - s, up) | acc]
    if n + 1 >= @max, do: acc, else: skip(rest, text, i, acc, n + 1)
  end

  defp cut(text, s, len, up) do
    w = :binary.copy(binary_part(text, s, min(len, @token_bytes)))
    if up, do: fold(w), else: w
  end

  defp fold(w), do: for(<<c <- w>>, into: <<>>, do: <<if(c in ?A..?Z, do: c + 32, else: c)>>)
end

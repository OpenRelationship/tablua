defmodule Moonflower.Charset do
  @moduledoc """
  A page's bytes as UTF-8. The set is the answer's `Content-Type` charset, else a `<meta charset>` (or its
  http-equiv form) in the first 1,024 bytes, else UTF-8 if the bytes are, else windows-1252, as browsers do.
  UTF-8 is mended (a bad byte becomes U+FFFD); ISO-8859-1, US-ASCII and windows-1252 are decoded as
  windows-1252, which the web's labels for them mean. Any other set is read with its non-ASCII bytes as U+FFFD,
  and the note says which set it was.

      {text, nil} = Charset.decode(body, "text/html; charset=windows-1252")
  """

  @latin ~w(windows-1252 cp1252 iso-8859-1 iso8859-1 latin1 l1 us-ascii ascii x-cp1252 iso-8859-15 latin-1)
  # windows-1252's 0x80-0x9F; the rest of its high half is Latin-1's
  @w1252 %{
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

  @doc "`{utf8, note}`: the note is nil, or says the page's set was not one moonflower decodes."
  def decode(body, content_type) do
    label = from_header(content_type) || from_meta(body)
    set = label && String.downcase(label)

    cond do
      set in [nil, "utf-8", "utf8"] and String.valid?(body) ->
        {body, nil}

      set in [nil, "utf-8", "utf8"] and set != nil ->
        {mend(body), nil}

      set == nil ->
        {latin(body), nil}

      set in @latin ->
        {latin(body), nil}

      true ->
        {ascii(body),
         "the page is in #{label}, which this browser does not decode; letters outside ASCII show as �"}
    end
  end

  defp from_header(nil), do: nil

  defp from_header(ct) do
    case Regex.run(~r/charset\s*=\s*"?([\w.:-]+)/i, ct) do
      [_, set] -> set
      _ -> nil
    end
  end

  defp from_meta(body) do
    head = binary_part(body, 0, min(byte_size(body), 1024))

    case Regex.run(~r/<meta[^>]+charset\s*=\s*["']?([\w.:-]+)/i, head) do
      [_, set] -> set
      _ -> nil
    end
  end

  # valid UTF-8 kept, each bad byte one U+FFFD
  defp mend(bin), do: bin |> mend([]) |> IO.iodata_to_binary()

  defp mend(bin, acc) do
    case :unicode.characters_to_binary(bin, :utf8, :utf8) do
      good when is_binary(good) -> [acc, good]
      {_, good, <<_, rest::binary>>} -> mend(rest, [acc, good, "�"])
      {_, good, <<>>} -> [acc, good]
    end
  end

  defp latin(bin), do: for(<<b <- bin>>, into: "", do: <<Map.get(@w1252, b, b)::utf8>>)

  defp ascii(bin), do: for(<<b <- bin>>, into: "", do: if(b < 0x80, do: <<b>>, else: "�"))
end

defmodule Moss.Sql.Printf do
  @moduledoc """
  printf()/format(), as SQLite's: `%[flags][width][.precision]type` with the
  flags `-`, `+`, space, `0`, `#` and `,` (thousands), `*` for a width or
  precision taken from the arguments, and the types `d i u f F e E g G x X o
  c s z q Q w %`. A missing argument is NULL; NULL prints as nothing (as
  `NULL` under %Q).
  """
  alias Moss.Sql.{Fp, Ops, Value}

  def format([nil | _]), do: nil

  def format([fmt | args]) do
    {out, _} = run(Value.to_text(fmt), args, [])
    Ops.check_size(IO.iodata_to_binary(out))
  end

  defp run("", args, acc), do: {Enum.reverse(acc), args}

  defp run("%" <> rest, args, acc) do
    {spec, rest, args} = spec(rest, args)

    case spec do
      :percent -> run(rest, args, ["%" | acc])
      :end -> run("", args, acc)
      {type, flags, width, prec} -> conv(type, flags, width, prec, rest, args, acc)
    end
  end

  defp run(s, args, acc) do
    case :binary.match(s, "%") do
      {at, _} -> run(binary_part(s, at, byte_size(s) - at), args, [binary_part(s, 0, at) | acc])
      :nomatch -> run("", args, [s | acc])
    end
  end

  defp spec(s, args) do
    {flags, s} = take_while(s, ~c"-+ 0#,!")
    {width, s, args} = number(s, args)

    {prec, s, args} =
      case s do
        "." <> more ->
          {p, more, args} = number(more, args)
          {p || 0, more, args}

        _ ->
          {nil, s, args}
      end

    case s do
      "" -> {:end, "", args}
      "%" <> rest -> {:percent, rest, args}
      <<t::utf8, rest::binary>> -> {{t, flags, width, prec}, rest, args}
    end
  end

  defp take_while(s, chars) do
    n = s |> :binary.bin_to_list() |> Enum.take_while(&(&1 in chars)) |> length()
    {binary_part(s, 0, n), binary_part(s, n, byte_size(s) - n)}
  end

  defp number("*" <> rest, args) do
    {v, args} = next(args)
    # as a written width is: past 100,000 it is 100,000 (an argument's 2,000,000,000 once made that many spaces)
    n = Value.to_integer(Value.to_number(v || 0))
    {max(min(n, 100_000), -100_000), rest, args}
  end

  defp number(s, args) do
    case Regex.run(~r/\A\d+/, s) do
      [d] ->
        {min(String.to_integer(d), 100_000),
         binary_part(s, byte_size(d), byte_size(s) - byte_size(d)), args}

      nil ->
        {nil, s, args}
    end
  end

  defp next([]), do: {nil, []}
  defp next([a | rest]), do: {a, rest}

  defp conv(t, flags, width, prec, rest, args, acc) do
    {v, args} = next(args)
    left = String.contains?(flags, "-")
    zero = String.contains?(flags, "0") and not left
    width = if is_integer(width) and width < 0, do: abs(width), else: width
    left = left or (is_integer(width) and width < 0)

    body =
      case t do
        c when c in [?d, ?i, ?u] ->
          int(v, flags, prec)

        c when c in [?f, ?F, ?e, ?E, ?g, ?G] ->
          Fp.format(real(v), c, prec || 6, flags)

        c when c in [?x, ?X, ?o] ->
          unsigned(v, c, flags, prec)

        ?c ->
          char(v)

        c when c in [?s, ?z] ->
          text(v, prec)

        ?q ->
          if v == nil, do: "(NULL)", else: String.replace(text(v, prec), "'", "''")

        ?Q ->
          if v == nil, do: "NULL", else: "'" <> String.replace(text(v, prec), "'", "''") <> "'"

        ?w ->
          String.replace(text(v, prec), "\"", "\"\"")

        _ ->
          ""
      end

    numeric = t in [?d, ?i, ?u, ?f, ?F, ?e, ?E, ?g, ?G, ?x, ?X, ?o]
    run(rest, args, [pad(body, width, left, zero and numeric) | acc])
  end

  defp pad(body, nil, _, _), do: body

  defp pad(body, w, left, zero) do
    n = String.length(body)

    cond do
      n >= w -> body
      left -> body <> String.duplicate(" ", w - n)
      zero -> zero_pad(body, w - n)
      true -> String.duplicate(" ", w - n) <> body
    end
  end

  defp zero_pad(<<s, rest::binary>>, n) when s in [?-, ?+, ?\s],
    do: <<s>> <> String.duplicate("0", n) <> rest

  defp zero_pad(body, n), do: String.duplicate("0", n) <> body

  defp int(v, flags, prec) do
    n = Value.to_integer(Value.to_number(v || 0))
    digits = Integer.to_string(abs(n))

    digits =
      if prec && String.length(digits) < prec,
        do: String.pad_leading(digits, prec, "0"),
        else: digits

    digits = if String.contains?(flags, ","), do: thousands(digits), else: digits
    signed(n < 0, digits, flags)
  end

  defp thousands(d) do
    d
    |> String.reverse()
    |> String.graphemes()
    |> Enum.chunk_every(3)
    |> Enum.map_join(",", &Enum.join/1)
    |> String.reverse()
  end

  defp signed(true, digits, _), do: "-" <> digits

  defp signed(false, digits, flags) do
    cond do
      String.contains?(flags, "+") -> "+" <> digits
      String.contains?(flags, " ") -> " " <> digits
      true -> digits
    end
  end

  defp real(v), do: Value.to_real(v || 0) || 0.0

  defp unsigned(v, c, flags, prec) do
    n = Value.to_integer(Value.to_number(v || 0))
    n = if n < 0, do: n + 18_446_744_073_709_551_616, else: n

    digits =
      case c do
        ?x -> Integer.to_string(n, 16) |> String.downcase()
        ?X -> Integer.to_string(n, 16)
        ?o -> Integer.to_string(n, 8)
      end

    digits =
      if prec && String.length(digits) < prec,
        do: String.pad_leading(digits, prec, "0"),
        else: digits

    if String.contains?(flags, "#") and n != 0,
      do:
        (case c do
           ?x -> "0x"
           ?X -> "0X"
           ?o -> "0"
         end) <> digits,
      else: digits
  end

  defp char(nil), do: ""
  defp char(v), do: v |> Value.to_text() |> String.first() || ""

  defp text(nil, _), do: ""
  defp text(v, nil), do: Value.to_text(v)
  defp text(v, prec), do: String.slice(Value.to_text(v), 0, prec)
end

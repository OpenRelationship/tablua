defmodule Moss.Sql.Functions do
  @moduledoc """
  SQLite's core scalar functions, by its rules: text functions count
  characters (blobs count bytes), case folds ASCII only (as SQLite without
  ICU), `substr` takes negative starts and lengths, `round` rounds half away
  from zero to a real, `abs` of text is a real. The date functions are
  `Moss.Sql.Date`, printf/format `Moss.Sql.Printf`. changes() and
  last_insert_rowid() are the compiler's (`Moss.Sql.Compile`).
  """
  alias Moss.Sql.{Date, Ops, Printf, Value}

  # name => {least, most} arguments (most nil: any)
  @arity %{
    "lower" => {1, 1},
    "upper" => {1, 1},
    "length" => {1, 1},
    "substr" => {2, 3},
    "substring" => {2, 3},
    "trim" => {1, 2},
    "ltrim" => {1, 2},
    "rtrim" => {1, 2},
    "replace" => {3, 3},
    "instr" => {2, 2},
    "abs" => {1, 1},
    "round" => {1, 2},
    "coalesce" => {2, nil},
    "ifnull" => {2, 2},
    "nullif" => {2, 2},
    "typeof" => {1, 1},
    "printf" => {1, nil},
    "format" => {1, nil},
    "date" => {0, nil},
    "time" => {0, nil},
    "datetime" => {0, nil},
    "julianday" => {0, nil},
    "unixepoch" => {0, nil},
    "strftime" => {1, nil},
    "iif" => {3, 3},
    "max" => {2, nil},
    "min" => {2, nil},
    "random" => {0, 0},
    "hex" => {1, 1},
    "quote" => {1, 1},
    "char" => {0, nil},
    "unicode" => {1, 1},
    "like" => {2, 3},
    "glob" => {2, 2},
    "sign" => {1, 1},
    "concat" => {1, nil},
    "concat_ws" => {2, nil}
  }

  @doc "Throws SQLite's error when `name` is not a function here or not for `n` arguments."
  def check!(name, n) do
    case @arity do
      %{^name => {lo, hi}} ->
        if n < lo or (hi != nil and n > hi),
          do: Ops.fail("wrong number of arguments to function #{name}()"),
          else: :ok

      _ ->
        Ops.fail("no such function: #{name}")
    end
  end

  def call(name, args, now)

  def call(f, [x], _) when f in ["lower", "upper"] do
    case x do
      nil ->
        nil

      x ->
        if f == "lower",
          do: Value.ascii_lower(Value.to_text(x)),
          else: Value.ascii_upper(Value.to_text(x))
    end
  end

  def call("length", [nil], _), do: nil
  def call("length", [{:blob, b}], _), do: byte_size(b)
  def call("length", [x], _), do: String.length(Value.to_text(x))

  def call("substring", args, now), do: call("substr", args, now)
  def call("substr", [nil | _], _), do: nil
  # an empty blob has no bytes to point at, and SQLite's substr gives NULL for it
  def call("substr", [{:blob, ""} | _], _), do: nil
  def call("substr", [_, nil | _], _), do: nil
  def call("substr", [_, _, nil], _), do: nil

  def call("substr", [x | rest], _) do
    {p1, p2} =
      case rest do
        [a] -> {int(a), nil}
        [a, b] -> {int(a), int(b)}
      end

    case x do
      {:blob, b} ->
        {:blob, sub(b, byte_size(b), p1, p2, &binary_part/3)}

      _ ->
        t = Value.to_text(x)
        sub(t, String.length(t), p1, p2, &String.slice/3)
    end
  end

  def call(f, [nil | _], _) when f in ["trim", "ltrim", "rtrim"], do: nil
  def call(f, [_, nil], _) when f in ["trim", "ltrim", "rtrim"], do: nil

  def call(f, [x | rest], _) when f in ["trim", "ltrim", "rtrim"] do
    chars = String.graphemes(Value.to_text(List.first(rest) || " "))
    t = Value.to_text(x)
    t = if f in ["trim", "ltrim"], do: drop_lead(t, chars), else: t

    if f in ["trim", "rtrim"],
      do: t |> String.reverse() |> drop_lead(chars) |> String.reverse(),
      else: t
  end

  def call("replace", [x, y, z], _) do
    # in SQLite's order: an empty pattern gives the text back before the replacement is looked at
    cond do
      x == nil or y == nil -> nil
      Value.to_text(y) == "" -> Value.to_text(x)
      z == nil -> nil
      true -> Ops.check_size(String.replace(Value.to_text(x), Value.to_text(y), Value.to_text(z)))
    end
  end

  def call("instr", [x, y], _) do
    cond do
      x == nil or y == nil -> nil
      y == "" or y == {:blob, ""} -> 1
      true -> instr(x, y)
    end
  end

  def call("abs", [nil], _), do: nil

  def call("abs", [x], _) when is_integer(x),
    do: if(x == Value.min_int(), do: Ops.fail("integer overflow"), else: abs(x))

  def call("abs", [x], _) when is_float(x), do: if(x < 0, do: -x, else: x)
  def call("abs", [x], now), do: call("abs", [Value.to_real(x)], now)

  def call("round", [nil | _], _), do: nil
  def call("round", [_, nil], _), do: nil
  def call("round", [x], now), do: call("round", [x, 0], now)

  def call("round", [x, n], _) do
    n = n |> int() |> max(0) |> min(30)
    r = Value.to_real(x)
    round_to(r, n)
  end

  def call("coalesce", args, _), do: Enum.find(args, &(&1 != nil))
  def call("ifnull", [a, b], _), do: if(a == nil, do: b, else: a)

  def call("typeof", [x], _), do: Value.type_name(x)
  def call(f, args, _) when f in ["printf", "format"], do: Printf.format(args)

  def call(f, args, now) when f in ["date", "time", "datetime", "julianday", "unixepoch"],
    do: Date.call(f, args, now)

  def call("strftime", [fmt | args], now), do: Date.strftime(fmt, args, now)
  def call("iif", [c, a, b], _), do: if(Value.truth(c) == true, do: a, else: b)

  def call("random", [], _),
    do: :rand.uniform(18_446_744_073_709_551_616) - 9_223_372_036_854_775_809

  def call("hex", [nil], _), do: ""
  def call("hex", [x], _), do: Base.encode16(Value.to_text(x))
  def call("quote", [x], _), do: quoted(x)

  def call("char", args, _) do
    for a <- args, into: "" do
      cp = int(a || 0)

      if cp >= 0 and cp <= 0x10FFFF and (cp < 0xD800 or cp > 0xDFFF),
        do: <<cp::utf8>>,
        else: <<0xFFFD::utf8>>
    end
  end

  def call("unicode", [nil], _), do: nil

  def call("unicode", [x], _) do
    case String.next_codepoint(Value.to_text(x)) do
      {<<c::utf8>>, _} -> c
      _ -> nil
    end
  end

  def call("like", [p, s | esc], _), do: Ops.like(s, p, List.first(esc))
  def call("glob", [p, s], _), do: Ops.glob(s, p)
  def call("sign", [nil], _), do: nil

  def call("sign", [x], _) do
    case if(is_binary(x), do: Value.parse_number(x), else: x) do
      n when is_number(n) and n > 0 -> 1
      n when is_number(n) and n < 0 -> -1
      n when is_number(n) -> 0
      _ -> nil
    end
  end

  def call("concat", args, _),
    do: Ops.check_size(args |> Enum.reject(&is_nil/1) |> Enum.map_join(&Value.to_text/1))

  def call("concat_ws", [nil | _], _), do: nil

  def call("concat_ws", [sep | args], _),
    do:
      Ops.check_size(
        args
        |> Enum.reject(&is_nil/1)
        |> Enum.map_join(Value.to_text(sep), &Value.to_text/1)
      )

  @doc """
  min(), max() and nullif() under a collation, as SQLite's: max keeps the
  first of equals, min the last.
  """
  def compare_call(f, args, coll) when f in ["max", "min"] do
    if Enum.member?(args, nil) do
      nil
    else
      Enum.reduce(args, fn v, best ->
        c = Value.compare(best, v, coll)
        if (f == "max" and c == :lt) or (f == "min" and c != :lt), do: v, else: best
      end)
    end
  end

  def compare_call("nullif", [a, b], coll) do
    if a != nil and b != nil and Value.compare(a, b, coll) == :eq, do: nil, else: a
  end

  # -- helpers -----------------------------------------------------------------------------------

  defp int(v), do: Value.to_integer(Value.to_number(v))

  # SQLite's substr arithmetic (func.c substrFunc), on characters or bytes
  defp sub(s, len, p1, p2, slice) do
    {p2, neg} =
      case p2 do
        nil -> {1_000_000_000, false}
        n when n < 0 -> {-n, true}
        n -> {n, false}
      end

    {p1, p2} =
      cond do
        p1 < 0 ->
          p1 = p1 + len
          if p1 < 0, do: {0, max(p2 + p1, 0)}, else: {p1, p2}

        p1 > 0 ->
          {p1 - 1, p2}

        p2 > 0 ->
          {0, p2 - 1}

        true ->
          {0, p2}
      end

    {p1, p2} =
      if neg do
        p1 = p1 - p2
        if p1 < 0, do: {0, max(p2 + p1, 0)}, else: {p1, p2}
      else
        {p1, p2}
      end

    p2 = if p1 + p2 > len, do: max(len - p1, 0), else: p2
    if p1 >= len, do: slice.(s, 0, 0), else: slice.(s, p1, p2)
  end

  defp drop_lead(t, chars) do
    case String.next_grapheme(t) do
      {g, rest} -> if g in chars, do: drop_lead(rest, chars), else: t
      nil -> t
    end
  end

  defp instr({:blob, a}, {:blob, b}) do
    case :binary.match(a, b) do
      {at, _} -> at + 1
      :nomatch -> 0
    end
  end

  defp instr(x, y) do
    {a, b} = {Value.to_text(x), Value.to_text(y)}

    case :binary.match(a, b) do
      {at, _} -> String.length(binary_part(a, 0, at)) + 1
      :nomatch -> 0
    end
  end

  # as SQLite's roundFunc: past 2^52 there is nothing to round; to a whole number directly; else %!.*f
  defp round_to(r, _) when r < -4_503_599_627_370_496.0 or r > 4_503_599_627_370_496.0, do: r
  defp round_to(r, 0), do: trunc(r + if(r < 0, do: -0.5, else: 0.5)) * 1.0
  defp round_to(r, n), do: Moss.Sql.Fp.round(r, n)

  defp quoted(nil), do: "NULL"
  defp quoted(v) when is_integer(v) or is_float(v), do: Value.to_text(v)
  defp quoted({:blob, b}), do: "X'" <> Base.encode16(b) <> "'"
  defp quoted(s), do: "'" <> String.replace(s, "'", "''") <> "'"
end

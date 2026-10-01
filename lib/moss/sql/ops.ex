defmodule Moss.Sql.Ops do
  @moduledoc """
  SQLite's operators over `Moss.Sql.Value`s: arithmetic (integer unless a
  real is involved, integer division truncating, overflow to real, division
  by zero NULL), `||`, the bit operators, comparisons under affinity and
  collation, LIKE (ASCII case folded) and GLOB, and CAST.
  """
  alias Moss.Sql.Value

  @max_int 9_223_372_036_854_775_807
  @min_int -9_223_372_036_854_775_808
  @max_text 16 * 1024 * 1024

  def fail(msg), do: throw({:sql_error, msg})

  @doc "Text or a blob past the size SQLite allows a run here."
  def check_size(v) when is_binary(v) and byte_size(v) > @max_text,
    do: fail("string or blob too big")

  def check_size({:blob, b} = v) when byte_size(b) > @max_text,
    do: fail("string or blob too big") && v

  def check_size(v), do: v

  def arith(_, nil, _), do: nil
  def arith(_, _, nil), do: nil

  def arith(op, a, b) do
    a = Value.to_number(a)
    b = Value.to_number(b)
    num(op, a, b)
  end

  defp num("+", a, b) when is_integer(a) and is_integer(b),
    do: int(a + b, fn -> a * 1.0 + b * 1.0 end)

  defp num("-", a, b) when is_integer(a) and is_integer(b),
    do: int(a - b, fn -> a * 1.0 - b * 1.0 end)

  defp num("*", a, b) when is_integer(a) and is_integer(b),
    do: int(a * b, fn -> a * 1.0 * (b * 1.0) end)

  defp num("/", _, 0), do: nil
  defp num("/", a, b) when is_integer(a) and is_integer(b), do: int(div(a, b), fn -> a / b end)

  defp num("%", a, b) when is_integer(a) and is_integer(b),
    do: if(b == 0, do: nil, else: rem(a, b))

  defp num("%", a, b) do
    {ia, ib} = {Value.to_integer(a), Value.to_integer(b)}
    if ib == 0, do: nil, else: rem(ia, ib) * 1.0
  end

  defp num("/", _, b) when b == 0, do: nil
  defp num("/", a, b), do: float_op(fn -> a / b end)
  defp num("+", a, b), do: float_op(fn -> a + b end)
  defp num("-", a, b), do: float_op(fn -> a - b end)
  defp num("*", a, b), do: float_op(fn -> a * b end)

  # past 64 bits SQLite does the operation again in reals
  defp int(n, real) when n > @max_int or n < @min_int, do: real.()
  defp int(n, _), do: n

  # SQLite's reals past the range are Inf; the BEAM has no Inf, so it is an error here
  defp float_op(f) do
    f.()
  rescue
    ArithmeticError -> fail("floating-point overflow")
  end

  def neg(nil), do: nil

  # as SQLite computes it, 0 - v (so -0.0 is 0.0)
  def neg(v), do: arith("-", 0, v)

  def bit(_, nil, _), do: nil
  def bit(_, _, nil), do: nil

  def bit(op, a, b) do
    # text by its leading integer, as CAST AS INTEGER reads it
    {a, b} = {Value.to_integer(a), Value.to_integer(b)}

    r =
      case op do
        "&" -> Bitwise.band(a, b)
        "|" -> Bitwise.bor(a, b)
        "<<" -> shift(a, b)
        ">>" -> shift(a, -b)
      end

    wrap(r)
  end

  defp shift(_a, b) when b >= 64, do: 0
  defp shift(a, b) when b <= -64, do: if(a < 0, do: -1, else: 0)
  defp shift(a, b) when b >= 0, do: Bitwise.bsl(a, b)
  defp shift(a, b), do: Bitwise.bsr(a, -b)

  defp wrap(n) do
    n = Bitwise.band(n, 0xFFFFFFFFFFFFFFFF)
    if n > @max_int, do: n - 0x10000000000000000, else: n
  end

  def bitnot(nil), do: nil
  def bitnot(v), do: wrap(Bitwise.bnot(Value.to_integer(v)))

  def concat(nil, _), do: nil
  def concat(_, nil), do: nil
  def concat(a, b), do: check_size(Value.to_text(a) <> Value.to_text(b))

  @doc """
  The affinity each side gets before two values compare (SQLite's datatype
  page, §4.2): numeric when either side is numeric, text when one side is text
  and the other has none.
  """
  def cmp_affinity(la, ra) do
    numeric = [:integer, :real, :numeric]

    cond do
      la in numeric and ra not in numeric -> {nil, :numeric}
      ra in numeric and la not in numeric -> {:numeric, nil}
      la == :text and ra == nil -> {nil, :text}
      ra == :text and la == nil -> {:text, nil}
      true -> {nil, nil}
    end
  end

  def prep(v, nil), do: v
  def prep(v, aff), do: Value.apply_affinity(v, aff)

  @doc "A comparison operator's result: 1, 0 or NULL."
  def compare(_, nil, _, _), do: nil
  def compare(_, _, nil, _), do: nil

  def compare(op, a, b, coll) do
    c = Value.compare(a, b, coll)

    bool(
      case op do
        "=" -> c == :eq
        "!=" -> c != :eq
        "<" -> c == :lt
        "<=" -> c != :gt
        ">" -> c == :gt
        ">=" -> c != :lt
      end
    )
  end

  @doc "IS: NULL is NULL, otherwise as `=`."
  def is(nil, nil, _), do: true
  def is(nil, _, _), do: false
  def is(_, nil, _), do: false
  def is(a, b, coll), do: Value.compare(a, b, coll) == :eq

  def bool(true), do: 1
  def bool(false), do: 0
  def bool(nil), do: nil

  def lnot(nil), do: nil
  def lnot(v), do: bool(not Value.truth(v))

  def land(a, b) do
    case {Value.truth(a), Value.truth(b)} do
      {false, _} -> 0
      {_, false} -> 0
      {true, true} -> 1
      _ -> nil
    end
  end

  def lor(a, b) do
    case {Value.truth(a), Value.truth(b)} do
      {true, _} -> 1
      {_, true} -> 1
      {false, false} -> 0
      _ -> nil
    end
  end

  # -- LIKE and GLOB -----------------------------------------------------------------------------

  def like(nil, _, _), do: nil
  def like(_, nil, _), do: nil
  # SQLite 3.53: a blob on either side never matches
  def like({:blob, _}, _, _), do: 0
  def like(_, {:blob, _}, _), do: 0

  def like(s, p, esc) do
    esc =
      case esc do
        nil -> nil
        e -> esc_char(Value.to_text(e))
      end

    s = Value.ascii_lower(Value.to_text(s))
    pat = like_pattern(String.to_charlist(Value.ascii_lower(Value.to_text(p))), esc, [])
    bool(wild(List.to_tuple(String.to_charlist(s)), List.to_tuple(pat)))
  end

  defp esc_char(e) do
    case String.to_charlist(e) do
      [c] -> c
      _ -> fail("ESCAPE expression must be a single character")
    end
  end

  defp like_pattern([], _e, acc), do: Enum.reverse(acc)
  defp like_pattern([e, c | p], e, acc) when e != nil, do: like_pattern(p, e, [{:lit, c} | acc])
  defp like_pattern([?% | p], e, acc), do: like_pattern(p, e, [:seq | acc])
  defp like_pattern([?_ | p], e, acc), do: like_pattern(p, e, [:one | acc])
  defp like_pattern([c | p], e, acc), do: like_pattern(p, e, [{:lit, c} | acc])

  def glob(nil, _), do: nil
  def glob(_, nil), do: nil
  def glob({:blob, _}, _), do: 0
  def glob(_, {:blob, _}), do: 0

  def glob(s, p) do
    pat = glob_pattern(String.to_charlist(Value.to_text(p)), [])
    bool(wild(List.to_tuple(String.to_charlist(Value.to_text(s))), List.to_tuple(pat)))
  end

  defp glob_pattern([], acc), do: Enum.reverse(acc)
  defp glob_pattern([?* | p], acc), do: glob_pattern(p, [:seq | acc])
  defp glob_pattern([?? | p], acc), do: glob_pattern(p, [:one | acc])

  defp glob_pattern([?[ | p] = all, acc) do
    {neg, p} = if match?([?^ | _], p), do: {true, tl(p)}, else: {false, p}

    case class(p, [], true) do
      {ranges, rest} -> glob_pattern(rest, [{:class, neg, ranges} | acc])
      nil -> glob_pattern(tl(all), [{:lit, ?[} | acc])
    end
  end

  defp glob_pattern([c | p], acc), do: glob_pattern(p, [{:lit, c} | acc])

  defp class([?] | rest], acc, true), do: class(rest, [{?], ?]} | acc], false)
  defp class([?] | rest], acc, false), do: {acc, rest}
  defp class([a, ?-, b | rest], acc, _) when b != ?], do: class(rest, [{a, b} | acc], false)
  defp class([x | rest], acc, _), do: class(rest, [{x, x} | acc], false)
  defp class([], _, _), do: nil

  # wildcard matching that backtracks only to the last `%`/`*`: at most |s| x |p| steps, every 65,536 of
  # them counted against the run's budget (Moss.Sql.Budget) so a pathological pattern cannot hang a run
  defp wild(s, p), do: elem(wild(s, p, 0, 0, -1, 0, 0), 0)

  defp wild(s, p, si, pi, star, mark, n) do
    slen = tuple_size(s)
    plen = tuple_size(p)

    cond do
      si < slen and pi < plen and elem(p, pi) == :seq ->
        wild(s, p, si, pi + 1, pi, si, n + 1)

      si < slen and pi < plen and one(elem(p, pi), elem(s, si)) ->
        wild(s, p, si + 1, pi + 1, star, mark, n + 1)

      si < slen and star >= 0 ->
        if rem(n, 65536) == 0, do: Moss.Sql.Budget.spend(1024)
        wild(s, p, mark + 1, star + 1, star, mark + 1, n + 1)

      si < slen ->
        {false, n}

      true ->
        rest = for i <- pi..(plen - 1)//1, do: elem(p, i)
        {Enum.all?(rest, &(&1 == :seq)), n}
    end
  end

  defp one(:one, _), do: true
  defp one({:lit, c}, c), do: true
  defp one({:lit, _}, _), do: false

  defp one({:class, neg, ranges}, c),
    do: neg != Enum.any?(ranges, fn {a, b} -> c >= a and c <= b end)

  defp one(:seq, _), do: false

  # -- CAST --------------------------------------------------------------------------------------

  def cast(nil, _), do: nil

  def cast(v, type) do
    case Value.affinity(type) do
      :integer -> Value.to_integer(v)
      :real -> Value.to_real(v)
      :text -> Value.to_text(v)
      :blob -> {:blob, Value.to_text(v)}
      :numeric -> cast_numeric(v)
    end
  end

  defp cast_numeric(v) when is_integer(v) or is_float(v), do: v

  defp cast_numeric(v) do
    case Value.to_number(v) do
      f when is_float(f) -> Value.apply_affinity(f, :numeric)
      n -> n
    end
  end
end

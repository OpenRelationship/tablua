defmodule Moss.Sql.Value do
  @moduledoc """
  A value of the agent's SQL, as SQLite's storage classes: `nil` (NULL), an
  integer (64-bit), a float (real), a binary (text) or `{:blob, binary}`.
  Here are SQLite's rules for them: affinity, comparison and collation, the
  sort keys indexes and ORDER BY use, and how numbers read and print as text.
  """

  @max_int 9_223_372_036_854_775_807
  @min_int -9_223_372_036_854_775_808

  def max_int, do: @max_int
  def min_int, do: @min_int

  @doc "A declared column type's affinity, by SQLite's five rules (§3.1 of its datatype page)."
  def affinity(nil), do: :blob

  def affinity(type) do
    t = String.upcase(type)

    cond do
      String.contains?(t, "INT") -> :integer
      String.contains?(t, ["CHAR", "CLOB", "TEXT"]) -> :text
      String.contains?(t, "BLOB") or t == "" -> :blob
      String.contains?(t, ["REAL", "FLOA", "DOUB"]) -> :real
      true -> :numeric
    end
  end

  @doc "A value stored under `aff`, converted as SQLite converts it."
  def apply_affinity(v, :text) when is_integer(v) or is_float(v), do: to_text(v)

  def apply_affinity(v, aff) when is_binary(v) and aff in [:integer, :numeric, :real] do
    case parse_number(v) do
      nil -> v
      n -> apply_affinity(n, aff)
    end
  end

  def apply_affinity(v, :real) when is_integer(v), do: v * 1.0

  def apply_affinity(v, aff) when is_float(v) and aff in [:integer, :numeric] do
    if v == Float.round(v) and v >= -9.223372036854775e18 and v <= 9.223372036854775e18,
      do: trunc(v),
      else: v
  end

  def apply_affinity(v, _), do: v

  @doc "A whole string that is a number, trimmed of spaces: an integer, a float, or nil."
  def parse_number(s) do
    t = String.trim(s, " ") |> String.trim("\t") |> String.trim("\n")

    cond do
      Regex.match?(~r/\A[+-]?\d+\z/, t) ->
        n = String.to_integer(String.trim_leading(t, "+"))
        if n > @max_int or n < @min_int, do: n * 1.0, else: n

      Regex.match?(~r/\A[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?\z/, t) ->
        to_float(t)

      true ->
        nil
    end
  end

  # Elixir's float parser wants digits around the point
  defp to_float(t) do
    t = Regex.replace(~r/\A([+-]?)\./, t, "\\g{1}0.")
    t = Regex.replace(~r/\.([eE]|\z)/, t, ".0\\1")
    t = if String.contains?(t, "."), do: t, else: Regex.replace(~r/([eE])/, t, ".0\\1")

    case Float.parse(String.trim_leading(t, "+")) do
      {f, ""} -> f
      _ -> nil
    end
  rescue
    ArgumentError ->
      if String.starts_with?(t, "-"), do: -1.7976931348623157e308, else: 1.7976931348623157e308
  end

  @doc "A value as a number for arithmetic: text by its longest numeric prefix, else 0."
  def to_number(nil), do: nil
  def to_number(v) when is_integer(v) or is_float(v), do: v
  def to_number({:blob, b}), do: to_number(b)

  def to_number(s) when is_binary(s) do
    t = String.trim_leading(s)

    case Regex.run(~r/\A[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?/, t) do
      [m | _] ->
        case parse_number(m) do
          nil -> 0
          n -> n
        end

      nil ->
        0
    end
  end

  @doc "The integer a value casts to (CAST AS INTEGER): text by its leading integer."
  def to_integer(nil), do: nil
  def to_integer(v) when is_integer(v), do: v

  def to_integer(v) when is_float(v) do
    cond do
      v != v -> 0
      v >= 9.223372036854775807e18 -> @max_int
      v <= -9.223372036854775808e18 -> @min_int
      true -> trunc(v)
    end
  end

  def to_integer({:blob, b}), do: to_integer(b)

  def to_integer(s) when is_binary(s) do
    case Regex.run(~r/\A\s*([+-]?\d+)/, s) do
      [_, d] -> d |> String.trim_leading("+") |> String.to_integer() |> clamp()
      nil -> 0
    end
  end

  defp clamp(n) when n > @max_int, do: @max_int
  defp clamp(n) when n < @min_int, do: @min_int
  defp clamp(n), do: n

  def to_real(nil), do: nil

  def to_real(v) do
    case to_number(v) do
      n when is_integer(n) -> n * 1.0
      f -> f
    end
  end

  @doc "A value as text, as SQLite renders it (a real with at least one decimal)."
  def to_text(nil), do: nil
  def to_text(s) when is_binary(s), do: s
  def to_text({:blob, b}), do: b
  def to_text(n) when is_integer(n), do: Integer.to_string(n)
  def to_text(f) when is_float(f), do: Moss.Sql.Fp.text(f)

  @doc "The storage class's name, as typeof() says it."
  def type_name(nil), do: "null"
  def type_name(v) when is_integer(v), do: "integer"
  def type_name(v) when is_float(v), do: "real"
  def type_name(v) when is_binary(v), do: "text"
  def type_name({:blob, _}), do: "blob"

  @doc "True, false or nil (NULL), as WHERE reads a value."
  def truth(nil), do: nil
  def truth(v) when is_integer(v) or is_float(v), do: v != 0
  def truth(v), do: to_number(v) != 0

  @doc """
  Compares two non-NULL values by SQLite's order (numbers, then text, then
  blobs) under a collation: `:lt`, `:eq` or `:gt`.
  """
  def compare(a, b, coll \\ :binary)

  def compare(a, b, _) when (is_integer(a) or is_float(a)) and (is_integer(b) or is_float(b)) do
    cond do
      a < b -> :lt
      a > b -> :gt
      true -> :eq
    end
  end

  def compare(a, _, _) when is_integer(a) or is_float(a), do: :lt
  def compare(_, b, _) when is_integer(b) or is_float(b), do: :gt

  def compare(a, b, coll) when is_binary(a) and is_binary(b),
    do: cmp(collate(a, coll), collate(b, coll))

  def compare(a, {:blob, _}, _) when is_binary(a), do: :lt
  def compare({:blob, _}, b, _) when is_binary(b), do: :gt
  def compare({:blob, a}, {:blob, b}, _), do: cmp(a, b)

  defp cmp(a, b) when a < b, do: :lt
  defp cmp(a, b) when a > b, do: :gt
  defp cmp(_, _), do: :eq

  @doc "Text as a collation compares it."
  def collate(s, :binary), do: s
  def collate(s, :nocase), do: ascii_lower(s)
  def collate(s, :rtrim), do: String.trim_trailing(s, " ")

  def ascii_lower(s), do: for(<<c <- s>>, into: "", do: <<if(c in ?A..?Z, do: c + 32, else: c)>>)
  def ascii_upper(s), do: for(<<c <- s>>, into: "", do: <<if(c in ?a..?z, do: c - 32, else: c)>>)

  @doc """
  The term a value sorts and is looked up by, in Erlang's order: NULL, then
  numbers (1 and 1.0 alike), then text under its collation, then blobs.
  """
  def key(nil, _), do: {0, 0}
  def key(v, _) when is_integer(v), do: {1, v}

  # a whole real keys as the integer it equals, so 2 and 2.0 are one value (to DISTINCT, GROUP BY, IN, UNIQUE)
  def key(v, _) when is_float(v) do
    if v == Float.round(v) and abs(v) < 9.223372036854775e18, do: {1, trunc(v)}, else: {1, v}
  end

  def key(v, coll) when is_binary(v), do: {2, collate(v, coll)}
  def key({:blob, b}, _), do: {3, b}

  @doc "SQLite's collation names; nil for one it does not have."
  def collation(name) do
    case String.upcase(name) do
      "BINARY" -> :binary
      "NOCASE" -> :nocase
      "RTRIM" -> :rtrim
      _ -> nil
    end
  end
end

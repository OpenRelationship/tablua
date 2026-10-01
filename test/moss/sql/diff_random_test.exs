defmodule Moss.Sql.DiffRandomTest do
  # The differential suite, generated (Arock PROJECT.md §14.7 item 9): random tables of mixed values (integers,
  # reals, numeric-looking text, text in both cases, blobs, NULL), then random expressions, predicates,
  # aggregates, updates and deletes, each run on Moss.Sql.Engine and on real SQLite and compared. Seeded, so a
  # failure repeats. Where SQLite leaves a result to its query plan (group_concat's order, which of 'abc' and
  # 'ABC' a NOCASE group shows, which of 2 and 2.0 DISTINCT keeps) the queries ask only what is defined.
  use ExUnit.Case, async: true

  @values [
    "0",
    "1",
    "-1",
    "2",
    "3",
    "7",
    "-3",
    "100",
    "9007199254740993",
    "0.5",
    "-1.25",
    "2.0",
    "1e3",
    "'1'",
    "'2.0'",
    "'-3'",
    "'abc'",
    "'ABC'",
    "'b'",
    "''",
    "' 3'",
    "'a%'",
    "x'01'",
    "x''",
    "NULL"
  ]
  @cols ~w(a b c d e rowid)
  @funcs [
    "abs(~)",
    "length(~)",
    "upper(~)",
    "lower(~)",
    "typeof(~)",
    "coalesce(~, ~)",
    "ifnull(~, ~)",
    "nullif(~, ~)",
    "substr(~, ~)",
    "substr(~, ~, ~)",
    "trim(~)",
    "instr(~, ~)",
    "max(~, ~)",
    "min(~, ~)",
    "cast(~ as integer)",
    "cast(~ as real)",
    "cast(~ as text)",
    "cast(~ as numeric)",
    "hex(~)",
    "quote(~)",
    "round(~)",
    "iif(~, ~, ~)",
    "replace(~, ~, ~)",
    "sign(~)",
    "printf('%d %s %.2f', ~, ~, ~)"
  ]
  @ops ~w(+ - * / % || = != < <= > >= and or & |)

  defp pick(list), do: Enum.at(list, :rand.uniform(length(list)) - 1)
  defp lit, do: pick(@values)

  defp expr(0), do: if(:rand.uniform(2) == 1, do: pick(@cols), else: lit())

  defp expr(d) do
    case :rand.uniform(7) do
      1 ->
        expr(0)

      2 ->
        "(#{expr(d - 1)} #{pick(@ops)} #{expr(d - 1)})"

      3 ->
        pick(@funcs)
        |> String.split("~")
        |> Enum.intersperse(nil)
        |> Enum.map_join(&(&1 || expr(d - 1)))

      4 ->
        "case when #{pred(d - 1)} then #{expr(d - 1)} else #{expr(d - 1)} end"

      5 ->
        "(#{expr(d - 1)} collate nocase)"

      6 ->
        "-#{expr(d - 1)}"

      7 ->
        "(#{pred(d - 1)})"
    end
  end

  defp pred(d) do
    case :rand.uniform(9) do
      1 ->
        "#{expr(d)} #{pick(~w(= != < <= > >= is))} #{expr(d)}"

      2 ->
        "#{pick(@cols)} #{pick(~w(= < > >=))} #{lit()}"

      3 ->
        "#{pick(@cols)} in (#{lit()}, #{lit()}, #{lit()})"

      4 ->
        "#{pick(@cols)} between #{lit()} and #{lit()}"

      5 ->
        "#{pick(@cols)} #{pick(["like", "not like", "glob"])} #{pick(~w('a%' '%b%' '_' 'A_C' '1%' '*a*'))}"

      6 ->
        "#{pick(@cols)} is #{pick(["null", "not null"])}"

      7 ->
        "(#{pred(max(d - 1, 0))} #{pick(["and", "or"])} #{pred(max(d - 1, 0))})"

      8 ->
        "not #{pred(max(d - 1, 0))}"

      9 ->
        "#{pick(@cols)} in (select b from r where #{pick(@cols)} > #{lit()})"
    end
  end

  defp table do
    rows = for _ <- 1..25, do: "(" <> Enum.map_join(1..5, ", ", fn _ -> lit() end) <> ")"

    [
      "create table r (a, b int, c text, d real, e text collate nocase)",
      "create index rb on r (b)",
      "create index rc on r (c)",
      "create index re on r (e, b)",
      "insert into r values " <> Enum.join(rows, ", ")
    ]
  end

  defp queries do
    for _ <- 1..30 do
      case :rand.uniform(6) do
        n when n <= 3 ->
          "select #{expr(2)}, #{expr(2)} from r where #{pred(2)} order by rowid"

        4 ->
          "select #{pick(~w(b c))} as k, count(*), count(a), sum(b), total(d), min(c), max(a), avg(b), length(group_concat(e)) from r where #{pred(1)} group by k"

        5 ->
          c = pick(~w(a b c d))
          "select distinct typeof(#{c}), #{c} from r where #{pred(2)}"

        6 ->
          "select * from r where #{pred(2)} order by #{pick(@cols)}, rowid limit #{:rand.uniform(10)} offset #{:rand.uniform(3) - 1}"
      end
    end
  end

  defp writes do
    for _ <- 1..6 do
      case :rand.uniform(3) do
        1 -> "update r set #{pick(~w(a b c d e))} = #{expr(1)} where #{pred(1)}"
        2 -> "delete from r where #{pred(1)}"
        3 -> "insert into r values (#{lit()}, #{lit()}, #{lit()}, #{lit()}, #{lit()})"
      end
      |> then(&[&1, "select rowid, * from r order by rowid"])
    end
    |> List.flatten()
  end

  test "random tables, expressions, predicates, groups and writes answer as SQLite's do" do
    diffs =
      for seed <- 1..150 do
        :rand.seed(:exsss, {seed, seed * 7, seed * 13})
        Moss.SqlDiff.differences(table() ++ queries() ++ writes() ++ queries())
      end
      |> List.flatten()

    assert diffs |> Enum.take(4) |> Enum.map(&Moss.SqlDiff.brief/1) == []
  end
end

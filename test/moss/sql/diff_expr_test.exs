defmodule Moss.Sql.DiffExprTest do
  # The differential suite, expressions (Arock PROJECT.md §14.7 item 9): each SELECT runs on Moss.Sql.Engine and
  # on real SQLite, and the answers (names, values and their types, or the error) must be the same.
  use ExUnit.Case, async: true

  @arith ~W{
    1+1 7/2 7.0/2 -7/2 7%3 -7%3 7%-3 10%3.5 10.5%3 1/0 1%0 1.0/0 5*1.5 2*3*4 1-2-3 2+3*4 (2+3)*4
    9223372036854775807+1 -9223372036854775808-1 9223372036854775807*2 -(-9223372036854775808)
    1<<3 1<<63 1<<64 -8>>1 5&3 5|3 ~5 ~-1 0x10 0xFF+1 -0x1 1e3 1.5e-3 .5 5. 3.0 100.0/3
    '3'+4 '3.5'*2 'abc'+1 '12abc'+0 '\x20\x204'+1 '1e3x'+0 'x'*2 null+1 1+null -null
    1=1.0 '1'=1 1<'a' 'a'<x'00' null=null null<>1 1!=2 1==1 2>1 2>=2 1<=0
  }

  @logic ~W{
    1\x20and\x200 1\x20or\x20null 0\x20and\x20null null\x20and\x20null null\x20or\x200 not\x201 not\x20null not\x200
    'a'\x20is\x20'a' null\x20is\x20null 1\x20is\x20not\x20null null\x20is\x20not\x201 1\x20is\x20distinct\x20from\x202
  }

  @exprs [
    "select 2 between 1 and 3, 4 not between 1 and 3, null between 1 and 2, 'b' between 'a' and 'c'",
    "select 1 in (1, 2), 3 in (1, 2), null in (1), 1 in (null, 1), 2 in (null, 1), 1 not in (2, 3), 2 not in (null)",
    "select 'a' in ('A', 'b'), 'a' collate nocase in ('A'), 1 in ('1'), '1' in (1)",
    "select 'abc' like 'a%', 'ABC' like 'a%', 'abc' like 'a_c', 'abc' like 'ab', 'a%c' like 'a\\%c' escape '\\'",
    "select 'é' like 'É', 'x' not like 'y', null like 'a', 'a' like null, 'aaa' like '%a%a%a%'",
    "select 'abc' glob 'a*', 'ABC' glob 'a*', 'abc' glob '[a-c]bc', 'abc' glob '[^a]bc', 'a?c' glob 'a?c', 'abc' glob '*'",
    "select case 1 when 1 then 'one' when 2 then 'two' end, case 3 when 1 then 'one' else 'other' end",
    "select case when 1 > 2 then 'a' when 2 > 1 then 'b' end, case when null then 1 else 0 end, case null when null then 1 else 0 end",
    "select cast('12.5abc' as integer), cast('abc' as real), cast(12.7 as integer), cast('  42  ' as integer)",
    "select cast(x'3132' as text), cast(1 as text), cast(1.5 as text), cast('9223372036854775808' as integer), cast(-12.7 as integer)",
    "select cast('1e3' as integer), cast('0x10' as integer), cast('1e3' as real), cast('5' as numeric), cast('5.0' as numeric), cast('5.5' as numeric)",
    "select typeof(cast('5' as numeric)), typeof(cast(5 as text)), typeof(cast(5 as real)), typeof(cast('x' as blob))",
    "select cast(0.1+0.2 as text), cast(1e20 as text), cast(1.0 as text), 1e15 || '', 1e16 || '', 1e17 || '', 0.000012 || ''",
    "select 123.456 || '', -2.5 || '', 100.0 || '', 0.1 || '', 3.0e10 || '', 1.7976931348623157e308 || '', 0.0001 || ''",
    "select 'a' || 1 || 2.0 || 'b', 'a' || null, x'41' || 'b', 1 || 2",
    "select typeof(1), typeof(1.0), typeof('a'), typeof(x'00'), typeof(null), typeof(1+1.0), typeof(7/2), typeof('1'+1)",
    "select max(1, 2), min(1, 2), max('a', 1), min('a', 1), max(1, null), min(3, 2.5, 4), max('b', 'a', 'c')",
    "select abs(-3), abs(-3.5), abs('x'), abs(null), abs('-4'), sign(-2), sign(0), sign(3.5), sign('x'), sign(null)",
    "select round(2.5), round(-2.5), round(1.2345, 2), round(1.5, 0), round(-0.5), round(1e20), round(2.675, 2), round(null), round(3.14159, 3)",
    "select lower('ABC é'), upper('abc é'), length('héllo'), length(x'0102'), length(12), length(1.5), length(null), length('')",
    "select substr('hello', 2), substr('hello', 2, 2), substr('hello', -2, 1), substr('hello', 2, -1), substr('hello', 0)",
    "select substr('hello', -10, 3), substr('hello', 10), substr(12345, 2, 2), substr('héllo', 2, 2), substr(x'010203', 2, 1), substring('abc', 2)",
    "select trim('  a  '), ltrim('  a  '), rtrim('  a  '), trim('xxaxx', 'x'), ltrim('xya', 'yx'), rtrim('axy', 'xy'), trim(null)",
    "select replace('aaa', 'a', 'bb'), replace('abc', '', 'x'), replace('abc', 'b', ''), replace(null, 'a', 'b'), replace(123, 2, 9)",
    "select instr('hello', 'l'), instr('hello', 'z'), instr('héllo', 'l'), instr('abc', ''), instr(null, 'a'), instr(12345, 34)",
    "select coalesce(null, null, 3), coalesce(null, 'a'), ifnull(null, 2), ifnull(1, 2), nullif(1, 1), nullif(1, 2), nullif('a', 'A')",
    "select iif(1, 'y', 'n'), iif(0, 'y', 'n'), iif(null, 'y', 'n'), hex('a'), hex(x'00ff'), hex(12), hex(null)",
    "select quote('it''s'), quote(1.5), quote(x'ab'), quote(null), quote(12), char(72, 105), unicode('é'), unicode('')",
    "select printf('%d', 42), printf('%5d|', 42), printf('%-5d|', 42), printf('%05d', 42), printf('%+d', 5), printf('% d', 5)",
    "select printf('%.2f', 3.14159), printf('%10.4f|', 2.5), printf('%.0f', 2.5), printf('%f', 1), printf('%e', 12345.678), printf('%.3e', 0)",
    "select printf('%g', 100000), printf('%g', 1000000), printf('%g', 1e-5), printf('%.3g', 3.14159), printf('%g', 0.0001), printf('%#g', 1.0)",
    "select printf('%x', 255), printf('%X', 255), printf('%o', 8), printf('%#x', 255), printf('%c', 'hello'), printf('%,d', 1234567)",
    "select printf('%s', 'hi'), printf('%5s|', 'ab'), printf('%-5s|', 'ab'), printf('%.2s', 'abcdef'), printf('%s', null), printf('%s', 3.0)",
    "select printf('%q', 'it''s'), printf('%Q', 'x'), printf('%Q', null), printf('%%'), printf('%d %s', 1), format('%s-%s', 1, 2)",
    "select printf('%d', '12abc'), printf('%d', 3.9), printf('%f', 'x'), printf('%i', -3), printf('%5.1s|', 'abc'), printf(null)",
    "select date('2024-01-31', '+1 month'), date('2024-03-31', '-1 month'), date('2024-02-29', '+1 year'), date('2024-01-01', '+1.5 days')",
    "select datetime('2024-01-01 10:00:00', '+90 minutes'), datetime('2024-01-01', '+1.5 hours'), datetime('2024-01-01 23:59:59', '+1 second')",
    "select date('2024-05-15', 'start of month'), date('2024-05-15', 'start of year'), datetime('2024-05-15 13:14:15', 'start of day')",
    "select date('2024-05-15', 'weekday 0'), date('2024-05-19', 'weekday 0'), date('2024-05-15', 'weekday 3'), date('2024-05-15', '-7 days')",
    "select julianday('2024-01-01'), julianday('2000-01-01 12:00:00'), datetime(1700000000, 'unixepoch'), datetime(2460310.5)",
    "select time('12:34:56.789'), time('12:34'), datetime('2024-01-01T10:00:00Z'), datetime('2024-01-01 10:00:00+02:00'), datetime('2024-01-01 10:00:00-01:30')",
    "select date('garbage'), date('2024-13-01'), date(null), date('2024-01-01', 'bogus'), unixepoch('2024-01-01'), unixepoch('1970-01-01 00:00:01')",
    "select strftime('%Y-%m-%d %H:%M:%S', '2024-07-04 15:07:09'), strftime('%j %W %U %w %u', '2024-03-01'), strftime('%s', '2024-01-01')",
    "select strftime('%H:%M %d/%m/%Y %j %u %e|%k|%I %p', '2024-07-04 15:07:09'), strftime('%f', '2024-01-01 10:00:01.5'), strftime('%F %T', '2024-02-03 04:05:06')",
    "select strftime('%W', '2024-01-01'), strftime('%W', '2023-01-01'), strftime('%U', '2023-01-01'), strftime('%j', '2024-12-31'), strftime('%V %G', '2024-12-30')",
    "select date('2024-01-01', '+1 month', '-1 day'), date('2024-01-31', 'start of month', '+1 month', '-1 day'), date(julianday('2024-06-01'))",
    "select datetime('2024-01-01 10:00:00', 'subsec'), time('10:00:00.25', 'subsec'), unixepoch('2024-01-01 00:00:00.5', 'subsec')",
    "select 1 collate nocase = 1, 'a' = 'A' collate nocase, 'a' collate nocase = 'A', 'a ' = 'a' collate rtrim, 'B' < 'a', 'B' < 'a' collate nocase",
    "select (select 1), (select 1 where 0), exists (select 1), not exists (select 1 where 0), 1 in (select 1), 2 in (select 1 union select null)",
    "select count(*), count(1), sum(1), total(1), avg(1), min(1), max(1), group_concat(1)",
    "select x, count(*) from (select 1 as x union all select 1 union all select 2) group by x",
    "select sum(x), total(x), avg(x), min(x), max(x), group_concat(x, ';'), count(x) from (select 1 as x union all select null union all select 2.5)",
    "select sum(x) from (select 9223372036854775807 as x union all select 1)",
    "select sum(x), total(x), avg(x) from (select 0.1 as x union all select 0.2 union all select 0.3)",
    "select sum(x) from (select '5' as x union all select '6')",
    "select group_concat(distinct x), count(distinct x), sum(distinct x) from (select 1 as x union all select 1 union all select 2)",
    "select 1 union select 2 union select 1 order by 1 desc",
    "select 1 as a union all select 2 order by a",
    "select 1 intersect select 1",
    "select 3 except select 3",
    "select 'x' as \"a b\", 1 as [c], 2 as `d`, 3 'e'",
    "select 1 limit 0",
    "select 1 limit 1 offset 1",
    "select null order by 1",
    "select random() is not null, typeof(random())",
    "select changes(), last_insert_rowid(), total_changes()",
    "select true, false, TRUE + 1",
    "select concat('a', null, 1), concat_ws('-', 'a', null, 'b')",
    "select like('a%', 'abc'), glob('a*', 'abc'), like('a', 'A')",
    "select printf('%.2f', 2.675), printf('%.1f', 0.25), printf('%.1f', 0.35), printf('%.0f', 0.5), printf('%.20f', 0.1)",
    "select printf('%e', 2.675e-5), printf('%.15f', 1.0/3), printf('%.3e', 2.6755), printf('%g', 2.675), printf('%.10g', 1.0/3), printf('%f', 1e20)",
    "select printf('%.2f', -1.005), printf('%g', 123456789), printf('%G', 1e-10), printf('%e', 0.1), printf('%.0e', 15), printf('%10.3g|', 3.14159)",
    "select round(1.005, 2), round(-1.005, 2), round(0.5), round(1234.5678, -1), round(9.995, 2), round(5e-324, 3)",
    "select 1.0/3 || '', 2.0/3 || '', 1e-7 || '', 123456789.123 || '', 1e300*10 is null"
  ]

  @errors [
    "select nope",
    "selec 1",
    "select 'abc",
    "select #",
    "select * from nope",
    "select 1 +",
    "select (1",
    "select coalesce(1)",
    "select nosuchfn(1)",
    "select count(1, 2)",
    "select abs()",
    "select 1 order by 2",
    "select count(*) from (select 1) where count(*) > 0"
  ]

  test "expressions answer as SQLite's do" do
    exprs = Enum.map(@arith ++ @logic, &("select " <> String.replace(&1, "\\x20", " ")))
    assert Moss.SqlDiff.differences(exprs) == []
    assert Moss.SqlDiff.differences(@exprs) == []
  end

  # reals SQLite prints by its own algorithm: ties, long fractions, the edges of the range, subnormals
  @reals ~w(0.1 0.2 0.3 1.0/3 2.0/3 1.0/7 2.675 1.005 0.125 0.5 1.5 2.5 -0.5 49.47 1e15 1e16 1e17 1e22 1e23 123456789.987654321
            9007199254740993.0 1.7976931348623157e308 2.2250738585072014e-308 5e-324 4.9e-324 1e-5 0.000123456 -1234.5678
            3.141592653589793 2.718281828459045 100.0 1e100 1.5e-7 0.1+0.2 1e300*1e-300 6.02214076e23)
  @formats ~w(%f %.2f %.0f %.10f %.20f %e %.3e %E %g %.3g %.10g %G %#g %!.17g %.15g %,.2f %+.1f %#.0f)

  test "reals print as SQLite prints them" do
    for r <- @reals do
      sql =
        "select #{r} || '', cast(#{r} as text), " <>
          Enum.map_join(@formats, ", ", &"printf('#{&1}', #{r})") <>
          ", round(#{r}, 1), round(#{r}, 2), round(#{r}, 5), round(#{r})"

      assert Moss.SqlDiff.differences([sql]) == []
    end
  end

  test "errors read as SQLite's" do
    assert Moss.SqlDiff.differences(@errors) == []
  end

  test "an expression is at most 1000 high, as SQLite counts it" do
    shapes = [
      fn n -> "select 1" <> String.duplicate("+1", n) end,
      fn n -> "select 'a'" <> String.duplicate(" || 'a'", n) end,
      fn n -> "select " <> String.duplicate("- ", n) <> "a from (select 1 as a)" end,
      fn n -> "select 1 where " <> Enum.map_join(2..n, " or ", &"#{&1} = 0") end,
      fn n -> "select " <> String.duplicate("(", n) <> "1" <> String.duplicate(")", n) end
    ]

    # SQLite itself overflows the NIF thread's C stack (SIGBUS, the whole VM gone) on an expression a few
    # hundred high, well inside its own limit; so it is asked only below that, and at the limit, where it
    # refuses before evaluating anything
    sql = for f <- shapes, n <- [300, 1000], do: f.(n)
    assert sql |> Moss.SqlDiff.differences() |> Enum.map(&String.slice(elem(&1, 0), 0, 40)) == []

    run = fn s -> Moss.Sql.Engine.exec(Moss.Sql.Engine.new(), s, [], fn _ -> :ok end) end
    answers = for f <- shapes, do: run.(f.(999)) |> elem(2) |> Map.get(:rows)
    assert answers == [[[1000]], [[String.duplicate("a", 1000)]], [[-1]], [], [[1]]]
  end
end

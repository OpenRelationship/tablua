defmodule Moss.Sql.DiffTableTest do
  # The differential suite, tables (Arock PROJECT.md §14.7 item 9): scripts of statements run in order on
  # Moss.Sql.Engine and on real SQLite; every statement's answer, or its error, must be the same.
  use ExUnit.Case, async: true

  @shop """
  create table person (id integer primary key, name text not null, city text collate nocase, age int)
  create table item (id integer primary key autoincrement, owner int references person(id), what text, price real, qty int default 1)
  create index item_owner on item (owner)
  create unique index person_name on person (name)
  insert into person values (1, 'Ana', 'Bend', 34), (2, 'bo', 'bend', 19), (3, 'Cy', 'Salem', null), (4, 'Di', null, 52)
  insert into person (name, city, age) values ('Ed', 'Portland', 41)
  select last_insert_rowid(), changes()
  insert into item (owner, what, price, qty) values (1, 'pen', 1.5, 3), (1, 'ink', 7, 1), (2, 'pad', 3.25, 2), (5, 'cup', 9.99, 1), (9, 'hat', 20, 1)
  insert into item (owner, what, price) values (3, 'map', 12)
  select * from person order by id
  select * from item order by id
  select name, age from person where age > 30 order by age desc
  select name from person where city = 'BEND' order by name
  select name from person where city = 'BEND' collate binary
  select name from person where age is null
  select name from person where age between 19 and 41 order by age
  select name from person where name in ('Ana', 'Cy', 'Zed') order by 1
  select name from person where name like 'b%'
  select name from person where name glob 'B*'
  select count(*), count(age), sum(age), avg(age), min(age), max(age), total(age) from person
  select city, count(*) as n from person group by city order by n desc, city
  select city, count(*) as n from person group by city having n > 1
  select upper(city) c, group_concat(name, '|') from person group by c order by c
  select p.name, i.what from person p join item i on i.owner = p.id order by p.name, i.what
  select p.name, i.what from person p left join item i on i.owner = p.id order by p.name, i.what
  select p.name, count(i.id) from person p left join item i on i.owner = p.id group by p.id order by p.id
  select p.name, sum(i.price * i.qty) as spent from person p join item i on i.owner = p.id group by p.name order by spent desc
  select name from person where id in (select owner from item where price > 5) order by name
  select name from person where id not in (select owner from item) order by name
  select name, (select count(*) from item where owner = person.id) as n from person order by n desc, name
  select name from person p where exists (select 1 from item where owner = p.id and qty > 1) order by name
  select name from person p where not exists (select 1 from item where owner = p.id) order by name
  select distinct city from person order by city
  select distinct lower(city) from person order by 1
  select * from person order by city, name
  select * from person order by city desc, name
  select * from person order by city nulls last, name
  select * from person order by age desc nulls first
  select * from person order by age limit 2
  select * from person order by age limit 2 offset 1
  select * from person order by age limit 1, 2
  select name, case when age >= 40 then 'old' when age >= 20 then 'mid' else 'young' end from person order by id
  select i.what, p.name from item i, person p where i.owner = p.id and p.city = 'bend' order by i.what
  select a.name, b.name from person a join person b on a.city = b.city and a.id < b.id order by 1, 2
  select what, price from item where price > (select avg(price) from item) order by price
  select owner, max(price), what from item group by owner order by owner
  select owner, min(price), what from item group by owner order by owner
  select x.n from (select name as n, age from person where age > 20) x order by x.n
  select count(*) from (select distinct city from person)
  select name from person union select what from item order by 1
  select name from person except select 'Ana' order by 1
  select owner from item intersect select id from person order by 1
  select typeof(age), typeof(price) from person, item where person.id = 1 and item.id = 1
  select name || ' (' || coalesce(city, '?') || ')' from person order by id
  select rowid, oid, _rowid_, id from person order by 1
  select * from item where id = 3
  select * from item where owner = 1 order by id
  select * from item where owner in (1, 3) order by id
  select * from item where price >= 7 and price < 13 order by price
  select * from item where id > 4 order by id
  select * from person where name > 'B' order by name
  """

  @constraints """
  create table t (id integer primary key, a text unique, b int not null default 0, c real check (c >= 0))
  insert into t (a, b, c) values ('x', 1, 1.5)
  insert into t (a, b, c) values ('x', 2, 2)
  insert into t (a, c) values ('y', -1)
  insert into t (a, b) values ('z', null)
  insert into t (id, a) values (1, 'w')
  insert or ignore into t (a, b) values ('x', 9)
  select changes()
  insert or replace into t (a, b) values ('x', 9)
  select * from t order by id
  replace into t (id, a, b) values (7, 'q', 3)
  insert into t (a) values ('n') on conflict (a) do nothing
  insert into t (a, b) values ('x', 5) on conflict (a) do update set b = b + excluded.b
  insert into t (a, b) values ('x', 5) on conflict (a) do update set b = excluded.b where b > 100
  insert into t (a, b) values ('q', 1) on conflict do nothing
  insert into t (id, a) values (7, 'r') on conflict (id) do update set a = excluded.a || '!'
  insert into t (a) values ('m') on conflict (b) do nothing
  select * from t order by id
  insert into t (a, b) values ('r', 1) returning id, a, b * 2 as double
  update t set b = b + 1 where a in ('x', 'q') returning *
  update t set a = 'x' where a = 'q'
  update or ignore t set a = 'x' where a = 'q'
  select changes()
  update or replace t set a = 'x' where a = 'q'
  select * from t order by id
  update t set id = 100 where a = 'x'
  update t set id = 'abc' where a = 'x'
  delete from t where b > 5 returning a
  delete from t where id = 100
  select count(*), changes() from t
  insert into t values ('5', 'five', 5, 5)
  insert into t values (6.0, 'six', 6, 6)
  insert into t values (6.5, 'sixhalf', 6, 6)
  select id, typeof(id) from t order by id
  create table u (k text primary key, v)
  insert into u values ('a', 1), ('b', 2)
  insert into u values ('a', 3)
  insert into u values (null, 4)
  insert into u values (null, 5)
  select k, v from u order by v
  create table v2 (a int, b int, unique (a, b))
  insert into v2 values (1, 1), (1, 2), (null, 1), (null, 1)
  insert into v2 values (1, 1)
  select count(*) from v2
  create table w (n int, s text, r real, x blob, y numeric, z)
  insert into w values ('42', 42, '4.0', 42, '42.0', '42')
  insert into w values ('4.5', 4.5, 4, 'b', '1e2', 1.0)
  insert into w values ('abc', null, 'x', x'00', 'x', x'01')
  select n, typeof(n), s, typeof(s), r, typeof(r), x, typeof(x), y, typeof(y), z, typeof(z) from w order by rowid
  select count(*) from w where n = 42
  select count(*) from w where n = '42'
  select count(*) from w where s = 42
  select count(*) from w where z = 42
  select count(*) from w where z = '42'
  """

  @schema """
  create table if not exists s (a)
  create table if not exists s (b)
  create table s (c)
  create table S (c)
  create table s2 (a, a)
  create index si on s (a)
  create index si on s (a)
  create index if not exists si on s (a)
  create index sj on nope (a)
  create index sk on s (nope)
  insert into s values (1), (2), (2)
  create unique index su on s (a)
  select type, name, tbl_name, sql from sqlite_master order by name
  drop index si
  drop index si
  drop index if exists si
  drop table nope
  drop table if exists nope
  alter table s add column b text default 'hi'
  alter table s add column c int not null
  alter table s add column b int
  select * from s order by rowid
  insert into s (a) values (3)
  select * from s order by rowid
  select sql from sqlite_master where name = 's'
  create table ct as select a, b, a * 2 as d from s where a > 1
  select * from ct order by rowid
  select sql from sqlite_master where name = 'ct'
  drop table s
  select name from sqlite_master order by name
  select * from s
  create table k (id integer primary key autoincrement, v)
  insert into k (v) values (1), (2), (3)
  delete from k where id = 3
  insert into k (v) values (4)
  select * from k order by id
  create table nk (id integer primary key, v)
  insert into nk (v) values (1), (2), (3)
  delete from nk where id = 3
  insert into nk (v) values (4)
  select * from nk order by id
  create table m (id int primary key, v)
  insert into m values (1, 'a'), (1.0, 'b')
  insert into m values ('1', 'c')
  select id, typeof(id) from m
  """

  @tx """
  create table a (x)
  begin
  insert into a values (1)
  insert into a values (2)
  select count(*) from a
  rollback
  select count(*) from a
  begin transaction
  insert into a values (3)
  commit
  select * from a
  commit
  rollback
  begin
  begin
  end
  insert into a values (4), (5)
  update a set x = x * 10
  select changes(), total_changes()
  delete from a
  select changes()
  """

  defp script(text), do: text |> String.split("\n", trim: true) |> Enum.map(&String.trim/1)

  test "a shop's tables, queried every way" do
    assert Moss.SqlDiff.differences(script(@shop)) == []
  end

  test "constraints, conflicts, upserts and affinity" do
    assert Moss.SqlDiff.differences(script(@constraints)) == []
  end

  test "the schema: create, index, alter, drop, sqlite_master" do
    assert Moss.SqlDiff.differences(script(@schema)) == []
  end

  test "transactions and changes()" do
    assert Moss.SqlDiff.differences(script(@tx)) == []
  end
end

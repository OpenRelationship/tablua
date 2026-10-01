defmodule Moss.Sql.Schema do
  @moduledoc """
  The schema of a database in memory: CREATE TABLE (an INTEGER PRIMARY KEY is
  the rowid; any other PRIMARY KEY and each UNIQUE is an index named as
  SQLite names it, `sqlite_autoindex_<table>_<n>`), CREATE INDEX, DROP,
  ALTER TABLE ADD COLUMN (existing rows read the new column's default, and
  the table's SQL gains the column as SQLite's does), and the rows of
  `sqlite_master`.

  A database is `%{tables: %{key => Table}, owner: %{index key => table
  key}, order: [{kind, key}], ...}`; keys are names lower-cased, as SQLite's
  names are case-insensitive.
  """
  alias Moss.Sql.{Compile, Ops, Table, Value}

  def fail(msg), do: Ops.fail(msg)

  def create_table(db, %{name: name} = st) do
    key = String.downcase(name)
    reserved!(key)

    cond do
      Map.has_key?(db.tables, key) ->
        if st.if_not_exists, do: db, else: fail("table #{name} already exists")

      Map.has_key?(db.owner, key) ->
        fail("there is already an index named #{name}")

      true ->
        t = table(st, db)

        db = %{
          db
          | tables: Map.put(db.tables, key, t),
            order: db.order ++ [{:table, key}],
            schema: true
        }

        Enum.reduce(t.indexes, db, &%{&2 | owner: Map.put(&2.owner, &1.key, key)})
    end
  end

  defp reserved!("sqlite_" <> _ = k), do: fail("object name reserved for internal use: #{k}")
  defp reserved!(_), do: :ok

  @doc "A table from its CREATE TABLE statement."
  def table(st, db) do
    key = String.downcase(st.name)
    cols = Enum.map(st.cols, &col/1)

    for {k, n} <- Enum.frequencies_by(cols, & &1.key),
        n > 1,
        do: fail("duplicate column name: #{Enum.find(cols, &(&1.key == k)).name}")

    if cols == [], do: fail("syntax error")

    col_pks =
      for {c, i} <- Enum.with_index(st.cols), c.pk, do: {[{c.name, nil}], c.pk.conflict, i, c.pk}

    t_pks = for {:pk, p} <- st.constraints, do: {p.cols, p.conflict, nil, nil}
    pks = col_pks ++ t_pks
    if length(pks) > 1, do: fail(~s(table "#{st.name}" has more than one primary key))

    find = fn cname ->
      Enum.find_index(cols, &(&1.key == String.downcase(cname))) ||
        fail("no such column: #{cname}")
    end

    {alias_, autoinc, pk_index} =
      case pks do
        [{[{c, _}], conflict, _, pk}] ->
          i = find.(c)
          integer = String.upcase(String.trim(Enum.at(cols, i).type || "")) == "INTEGER"
          {desc, autoinc} = if pk, do: {pk.desc, pk.autoinc}, else: {false, false}

          cond do
            integer and not desc -> {i, autoinc, nil}
            autoinc -> fail("AUTOINCREMENT is only allowed on an INTEGER PRIMARY KEY")
            true -> {nil, false, {[{c, nil}], conflict}}
          end

        [{cs, conflict, _, _}] ->
          {nil, false, {cs, conflict}}

        [] ->
          {nil, false, nil}
      end

    uniques =
      Enum.flat_map(Enum.zip(st.cols, cols), fn {c, _} ->
        if c.unique, do: [{[{c.name, nil}], c.unique}], else: []
      end) ++ for({:unique, u} <- st.constraints, do: {u.cols, u.conflict})

    autos = if(pk_index, do: [pk_index], else: []) ++ uniques

    indexes =
      autos
      |> Enum.with_index(1)
      |> Enum.map(fn {{cs, conflict}, n} ->
        %{
          name: "sqlite_autoindex_#{st.name}_#{n}",
          key: "sqlite_autoindex_#{key}_#{n}",
          table: key,
          cols: Enum.map(cs, fn {c, coll} -> index_col(cols, find.(c), coll) end),
          unique: true,
          conflict: conflict,
          auto: true,
          tree: :gb_sets.empty(),
          sql: nil
        }
      end)

    checks =
      Enum.flat_map(st.cols, & &1.checks) ++ for({:check, c} <- st.constraints, do: c)

    _ = db

    Table.new(
      name: st.name,
      key: key,
      sql: st.sql,
      cols: cols,
      alias: alias_,
      autoinc: autoinc,
      checks: checks,
      indexes: indexes
    )
  end

  defp col(c) do
    %{
      name: c.name,
      key: String.downcase(c.name),
      type: c.type,
      aff: Value.affinity(c.type),
      coll: c.collate && Value.collation(c.collate),
      notnull: c.notnull,
      default: c.default
    }
  end

  defp index_col(cols, i, coll) do
    c = Enum.at(cols, i)

    coll =
      case coll do
        nil -> c.coll || :binary
        name -> Value.collation(name) || fail("no such collation sequence: #{name}")
      end

    {i, coll}
  end

  def create_index(db, st) do
    key = String.downcase(st.name)
    tkey = String.downcase(st.table)
    reserved!(key)

    cond do
      Map.has_key?(db.owner, key) ->
        if st.if_not_exists, do: db, else: fail("index #{st.name} already exists")

      Map.has_key?(db.tables, key) ->
        fail("there is already a table named #{st.name}")

      not Map.has_key?(db.tables, tkey) ->
        fail("no such table: main.#{st.table}")

      true ->
        t = db.tables[tkey]

        cols =
          Enum.map(st.cols, fn {c, coll} ->
            case Table.col_index(t, String.downcase(c)) do
              i when is_integer(i) -> index_col(t.cols, i, coll)
              _ -> fail("no such column: #{c}")
            end
          end)

        ix = %{
          name: st.name,
          key: key,
          table: tkey,
          cols: cols,
          unique: st.unique,
          conflict: nil,
          auto: false,
          tree: :gb_sets.empty(),
          sql: st.sql
        }

        t = Table.add_index(t, ix)

        %{
          db
          | tables: Map.put(db.tables, tkey, t),
            owner: Map.put(db.owner, key, tkey),
            order: db.order ++ [{:index, key}],
            schema: true
        }
    end
  end

  def drop_table(db, %{name: name, if_exists: ie}) do
    key = String.downcase(name)

    case db.tables do
      %{^key => t} ->
        owner = Enum.reduce(t.indexes, db.owner, &Map.delete(&2, &1.key))
        keys = MapSet.new([{:table, key} | Enum.map(t.indexes, &{:index, &1.key})])

        %{
          db
          | tables: Map.delete(db.tables, key),
            owner: owner,
            schema: true,
            order: Enum.reject(db.order, &MapSet.member?(keys, &1)),
            dropped: MapSet.put(db.dropped, key)
        }

      _ ->
        if ie, do: db, else: fail("no such table: #{name}")
    end
  end

  def drop_index(db, %{name: name, if_exists: ie}) do
    key = String.downcase(name)

    case db.owner do
      %{^key => tkey} ->
        t = db.tables[tkey]
        ix = Enum.find(t.indexes, &(&1.key == key))

        if ix.auto,
          do: fail("index associated with UNIQUE or PRIMARY KEY constraint cannot be dropped")

        t = %{t | indexes: Enum.reject(t.indexes, &(&1.key == key))}

        %{
          db
          | tables: Map.put(db.tables, tkey, t),
            owner: Map.delete(db.owner, key),
            schema: true,
            order: List.delete(db.order, {:index, key})
        }

      _ ->
        if ie, do: db, else: fail("no such index: #{name}")
    end
  end

  def alter_add(db, %{table: tname, col: c, text: text}, ctx) do
    tkey = String.downcase(tname)
    t = db.tables[tkey] || fail("no such table: #{tname}")

    if Table.col_index(t, String.downcase(c.name)) not in [nil, :rowid],
      do: fail("duplicate column name: #{c.name}")

    if c.pk, do: fail("Cannot add a PRIMARY KEY column")
    if c.unique, do: fail("Cannot add a UNIQUE column")

    default =
      case c.default do
        nil -> nil
        {:lit, v} -> v
        _ -> fail("Cannot add a column with non-constant default")
      end

    if c.notnull && default == nil,
      do: fail("Cannot add a NOT NULL column with default value NULL")

    _ = ctx

    col = col(c)
    default = Value.apply_affinity(default, col.aff)
    rows = :gb_trees.map(fn _, row -> Tuple.insert_at(row, tuple_size(row), default) end, t.rows)
    sql = add_to_sql(t.sql, text)

    t = %{t | cols: t.cols ++ [col], rows: rows, sql: sql, checks: t.checks ++ c.checks}
    %{db | tables: Map.put(db.tables, tkey, t), schema: true}
  end

  # the column's text before the definition's closing parenthesis, as SQLite edits its schema
  defp add_to_sql(sql, text) do
    trimmed = String.trim_trailing(sql)
    {head, ")"} = String.split_at(trimmed, -1)
    String.trim_trailing(head) <> ", " <> text <> ")"
  end

  @doc "A table made from a query's columns (CREATE TABLE ... AS SELECT), with SQLite's declared types."
  def as_table(name, names, affs) do
    cols =
      Enum.zip(names, affs)
      |> Enum.map(fn {n, a} ->
        type = %{integer: "INT", real: "REAL", text: "TEXT", numeric: "NUM"}[a]

        q =
          if Regex.match?(~r/\A[A-Za-z_][A-Za-z0-9_]*\z/, n),
            do: n,
            else: ~s("#{String.replace(n, ~s("), ~s(""))}")

        {%{
           name: n,
           type: type,
           pk: nil,
           notnull: nil,
           unique: nil,
           checks: [],
           default: nil,
           collate: nil
         }, if(type, do: q <> " " <> type, else: q)}
      end)

    sql = "CREATE TABLE #{name}(" <> Enum.map_join(cols, ",", &elem(&1, 1)) <> ")"

    %{
      name: name,
      if_not_exists: false,
      cols: Enum.map(cols, &elem(&1, 0)),
      constraints: [],
      sql: sql
    }
  end

  @doc "The rows of `sqlite_master`: type, name, tbl_name, rootpage, sql."
  def master_rows(db) do
    Enum.flat_map(db.order, fn
      {:table, k} ->
        t = db.tables[k]

        [["table", t.name, t.name, 0, t.sql]] ++
          for ix <- t.indexes, ix.auto, do: ["index", ix.name, t.name, 0, nil]

      {:index, k} ->
        t = db.tables[db.owner[k]]
        ix = Enum.find(t.indexes, &(&1.key == k))
        [["index", ix.name, t.name, 0, ix.sql]]
    end)
  end

  @doc "A column's default for a new row: its DEFAULT, evaluated now, under its affinity."
  def default(col, ctx) do
    case col.default do
      nil ->
        nil

      e ->
        scope = %{id: make_ref(), sources: [], outer: nil, aliases: %{}, agg: nil, ctx: ctx}
        {f, _, _} = Compile.expr(e, scope)
        f.(%{rows: {}, outer: nil, aggs: nil})
    end
  end
end

defmodule Moss.Sql.Table do
  @moduledoc """
  A table in memory: its columns, its rows in a `:gb_trees` by rowid (so a
  scan is in rowid order, as SQLite's), and its indexes, each a `:gb_sets`
  of `{[key, ...], rowid}` in SQLite's order (`Moss.Sql.Value.key/2`), which
  answers equality and ranges and enforces UNIQUE.

  A row is a tuple of its column values. A column is `%{name, key, type,
  aff, coll, notnull, default, checks}`; `alias` is the column that is the
  rowid (INTEGER PRIMARY KEY), if any.
  """
  alias Moss.Sql.Value

  defstruct [
    :name,
    :key,
    :sql,
    cols: [],
    alias: nil,
    autoinc: false,
    seq: 0,
    checks: [],
    rows: nil,
    indexes: [],
    size: 0
  ]

  # below every rowid, for the lower bound of an index range
  @low -18_446_744_073_709_551_616
  @high 18_446_744_073_709_551_616

  def new(fields), do: struct(__MODULE__, Keyword.put(fields, :rows, :gb_trees.empty()))

  def count(t), do: :gb_trees.size(t.rows)

  def get(t, rowid) do
    case :gb_trees.lookup(rowid, t.rows) do
      {:value, row} -> row
      :none -> nil
    end
  end

  @doc "The column's position, or nil; `:rowid` for rowid/oid/_rowid_ that no column shadows."
  def col_index(t, key) do
    case Enum.find_index(t.cols, &(&1.key == key)) do
      nil -> if key in ["rowid", "oid", "_rowid_"], do: :rowid, else: nil
      i -> i
    end
  end

  @doc "The rowid a new row gets: the largest plus one (or past the AUTOINCREMENT high-water mark)."
  def next_rowid(t) do
    max = if :gb_trees.is_empty(t.rows), do: 0, else: elem(:gb_trees.largest(t.rows), 0)
    n = if t.autoinc, do: max(max, t.seq) + 1, else: max + 1
    if n > Value.max_int(), do: throw({:sql_error, "database or disk is full"}), else: n
  end

  @doc "Puts a row (new or replacing the one at its rowid) in the table and its indexes."
  def put(t, rowid, row) do
    t =
      case get(t, rowid) do
        nil -> t
        _ -> delete(t, rowid)
      end

    indexes = Enum.map(t.indexes, &%{&1 | tree: :gb_sets.add({keys(&1, row), rowid}, &1.tree)})
    seq = if t.autoinc, do: max(t.seq, rowid), else: t.seq

    %{
      t
      | rows: :gb_trees.insert(rowid, row, t.rows),
        indexes: indexes,
        seq: seq,
        size: t.size + size(row)
    }
  end

  def delete(t, rowid) do
    case get(t, rowid) do
      nil ->
        t

      row ->
        indexes =
          Enum.map(t.indexes, &%{&1 | tree: :gb_sets.delete_any({keys(&1, row), rowid}, &1.tree)})

        %{t | rows: :gb_trees.delete(rowid, t.rows), indexes: indexes, size: t.size - size(row)}
    end
  end

  @doc "A row's key in an index."
  def keys(index, row),
    do: Enum.map(index.cols, fn {i, coll} -> Value.key(elem(row, i), coll) end)

  @doc "The rows a new or changed row would collide with: `[{index, rowid}]` (UNIQUE ones, NULLs never collide)."
  def conflicts(t, row, self) do
    for ix <- t.indexes,
        ix.unique,
        k = keys(ix, row),
        not Enum.member?(k, {0, 0}),
        rowid <- eq(ix, k),
        rowid != self,
        do: {ix, rowid}
  end

  @doc "The rowids under an index whose leading keys are `prefix`."
  def eq(ix, prefix) do
    n = length(prefix)
    iter = :gb_sets.iterator_from({prefix, @low}, ix.tree)
    take_eq(iter, prefix, n, [])
  end

  defp take_eq(iter, prefix, n, acc) do
    case :gb_sets.next(iter) do
      {{k, rowid}, iter} ->
        if Enum.take(k, n) == prefix,
          do: take_eq(iter, prefix, n, [rowid | acc]),
          else: Enum.reverse(acc)

      :none ->
        Enum.reverse(acc)
    end
  end

  @doc """
  The rowids whose first index key lies between `lo` and `hi`, each
  `{key, inclusive?}` or nil for open (NULLs are never in a range).
  """
  def range(ix, lo, hi) do
    start =
      case lo do
        nil -> {[{0, @high}], @high}
        {k, true} -> {[k], @low}
        {k, false} -> {[k, {9, 0}], @high}
      end

    take_range(:gb_sets.iterator_from(start, ix.tree), lo, hi, [])
  end

  defp take_range(iter, lo, hi, acc) do
    case :gb_sets.next(iter) do
      {{[k | _], rowid}, iter} ->
        cond do
          k == {0, 0} -> take_range(iter, lo, hi, acc)
          lo != nil and not elem(lo, 1) and k == elem(lo, 0) -> take_range(iter, lo, hi, acc)
          within(k, hi) -> take_range(iter, lo, hi, [rowid | acc])
          true -> Enum.reverse(acc)
        end

      :none ->
        Enum.reverse(acc)
    end
  end

  defp within(_k, nil), do: true
  defp within(k, {h, true}), do: k <= h or k == h
  defp within(k, {h, false}), do: k < h and k != h

  @doc "Builds an index over the rows already in the table."
  def add_index(t, ix) do
    tree =
      :gb_trees.to_list(t.rows)
      |> Enum.map(fn {rowid, row} -> {keys(ix, row), rowid} end)
      |> :gb_sets.from_list()

    ix = %{ix | tree: tree}

    if ix.unique, do: unique!(t, ix)
    %{t | indexes: t.indexes ++ [ix]}
  end

  defp unique!(t, ix) do
    ix.tree
    |> :gb_sets.to_list()
    |> Enum.reject(fn {k, _} -> Enum.member?(k, {0, 0}) end)
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.find(fn [{a, _}, {b, _}] -> a == b end)
    |> case do
      nil -> :ok
      _ -> throw({:sql_error, "UNIQUE constraint failed: " <> index_cols(t, ix)})
    end
  end

  @doc "`t.a, t.b`: an index's columns as SQLite names them in a constraint's error."
  def index_cols(t, ix) do
    Enum.map_join(ix.cols, ", ", fn
      {:rowid, _} -> t.name <> ".rowid"
      {i, _} -> t.name <> "." <> Enum.at(t.cols, i).name
    end)
  end

  @doc "About the bytes a row takes, for the database's size limit."
  def size(row) do
    row
    |> Tuple.to_list()
    |> Enum.reduce(4, fn
      v, n when is_binary(v) -> n + 5 + byte_size(v)
      {:blob, b}, n -> n + 5 + byte_size(b)
      _, n -> n + 9
    end)
  end
end

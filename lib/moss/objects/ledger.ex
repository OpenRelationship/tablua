defmodule Moss.Objects.Ledger do
  @moduledoc """
  The node's own record of its packs (Arock PROJECT.md §15 item 4), in files
  beside the replica so every BEAM on the work dir reads the same, and in JSON
  so nothing is decoded into terms:

    * `.gen/<id>`: an awake computer's chain, `{"gen": n, "packed": {name: size}}`:
      which wake of the computer it is (its file's `user_version`) and which of
      its segments are already in a pack. Written at its wake and by each pack,
      removed at its sleep, all under the computer's lock.
    * `.slept/<id>`: the chain of the computer's last snapshot, written once its
      whole file is in the store, at a sleep or at a cut while it stays awake
      (`Moss.Objects.Snapshot.cut/3`), which ends its chain.
    * `.packs/<name>.json`: a pack's header, so the node knows which packs hold
      which computer's segments with no index in the store. The folder is also
      the mark of a work dir that has met the store: a node without it lists
      its packs before anything wakes (`Moss.Objects.Recover`).

  A pack is garbage once every chain in it is no newer than its computer's
  snapshot (`garbage?/1`).
  """
  alias Moss.Litestream

  defp root, do: Litestream.replica_root()
  defp file(kind, name), do: Path.join([root(), kind, name])

  def gen(id), do: read(file(".gen", id))
  def put_gen(id, gen, packed), do: write(file(".gen", id), %{"gen" => gen, "packed" => packed})
  def drop_gen(id), do: File.rm(file(".gen", id))

  def slept(id) do
    case read(file(".slept", id)) do
      %{"gen" => g} -> g
      nil -> nil
    end
  end

  def put_slept(id, gen), do: write(file(".slept", id), %{"gen" => gen})
  def drop_slept(id), do: File.rm(file(".slept", id))

  @doc "Computers with a `.slept` record."
  def slept_ids, do: names(".slept", "")

  @doc "Every pack the node knows, name => entries."
  def packs do
    for n <- names(".packs", ".json"),
        e = read(file(".packs", n <> ".json")),
        into: %{},
        do: {n, e["entries"]}
  end

  def put_pack(name, entries), do: write(file(".packs", name <> ".json"), %{"entries" => entries})
  def drop_pack(name), do: File.rm(file(".packs", name <> ".json"))

  @doc "Whether this work dir's packs have been listed from the store at least once."
  def known?, do: File.dir?(Path.join(root(), ".packs"))
  def mark_known, do: File.mkdir_p!(Path.join(root(), ".packs"))

  @doc "The chains (`{id, gen}`) a pack's entries hold."
  def chains(entries), do: entries |> Enum.map(&{&1["id"], &1["gen"]}) |> Enum.uniq()

  @doc "Whether every chain in a pack is covered by its computer's snapshot."
  def garbage?(entries), do: Enum.all?(chains(entries), fn {id, g} -> (slept(id) || -1) >= g end)

  defp names(kind, ext) do
    for f <- Path.wildcard(Path.join([root(), kind, "*" <> ext])), do: Path.basename(f, ext)
  end

  defp read(path) do
    with {:ok, text} <- File.read(path), {:ok, v} <- Jason.decode(text), do: v, else: (_ -> nil)
  end

  # written beside and renamed, so a reader never sees half a record
  defp write(path, value) do
    File.mkdir_p!(Path.dirname(path))
    tmp = "#{path}.#{System.unique_integer([:positive])}.tmp"
    File.write!(tmp, Jason.encode!(value))
    File.rename!(tmp, path)
  end
end

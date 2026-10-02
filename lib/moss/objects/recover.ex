defmodule Moss.Objects.Recover do
  @moduledoc """
  What a node does with its packs when it starts (Arock PROJECT.md §15 item 4),
  before any computer wakes:

    1. It lists its packs in the store and reads the header of each one its
       ledger does not know (one ranged GET each): every pack, on a node whose
       disk was lost or a new machine given a dead node's token; only a pack
       put just before a crash, otherwise.
    2. A computer with a chain in those packs, not awake on the node (no file,
       no chain on the node) and not known to have slept since, was awake when
       the node lost its disk. If its snapshot in the store is of that chain or
       a later one, it slept after all, and the ledger says so. Otherwise its
       chain's entries are taken from every pack holding them (one ranged GET
       per pack), checked, and Litestream rebuilds its file from them; the file
       goes up as its snapshot, so it is asleep like any other and wakes on
       any node.
    3. The packer then deletes every pack all of whose computers are asleep.

  A new machine takes over a dead node's computers by being given that node's
  token (its name and the claims of its disks): it starts with an empty work
  dir, so step 1 reads every pack. A computer whose rebuild fails stays as its
  last snapshot, and its packs stay for the next start.
  """
  require Logger
  alias Moss.{Litestream, Objects}
  alias Moss.Objects.{Ledger, Lock, Pack, Snapshot}

  @first 64 * 1024

  @doc "`{:ok, %{read: packs, rebuilt: ids, asleep: ids}}`, or an error when a work dir new to the store cannot list."
  def run do
    fresh = not Ledger.known?()

    with {:ok, listed} <- Objects.pack_list(),
         known = Ledger.packs(),
         {:ok, read} <- learn(Map.keys(listed) -- Map.keys(known)) do
      Ledger.mark_known()

      result =
        lost()
        |> Task.async_stream(&recover/1, timeout: :infinity, max_concurrency: 8)
        |> Enum.map(fn {:ok, r} -> r end)

      {:ok,
       %{
         read: read,
         rebuilt: for({:rebuilt, id} <- result, do: id),
         asleep: for({:asleep, id} <- result, do: id)
       }}
    else
      {:error, why} when fresh ->
        {:error, why}

      {:error, why} ->
        tap({:ok, %{read: 0, rebuilt: [], asleep: []}}, fn _ ->
          Logger.warning("packs not listed: #{inspect(why)}")
        end)
    end
  end

  # each unknown pack's header into the ledger
  defp learn(names) do
    names
    |> Task.async_stream(fn n -> {n, header(n)} end, timeout: 120_000, max_concurrency: 16)
    |> Enum.reduce_while({:ok, 0}, fn
      {:ok, {name, {:ok, entries}}}, {:ok, n} ->
        Ledger.put_pack(name, entries)
        {:cont, {:ok, n + 1}}

      {:ok, {name, other}}, _ ->
        {:halt, {:error, {name, other}}}
    end)
  end

  @doc "A pack's header from the store: its first bytes, and the rest of the header when it is longer."
  def header(name) do
    with {:ok, head} <- Objects.pack_get(name, {0, @first - 1}) do
      case Pack.header_size(head) do
        {:ok, n} when n <= byte_size(head) ->
          Pack.header(head)

        {:ok, n} ->
          with {:ok, rest} <- Objects.pack_get(name, {byte_size(head), n - 1}),
               do: Pack.header(head <> rest)

        :short ->
          {:error, "#{name} is shorter than a header"}

        e ->
          e
      end
    end
  end

  # computers whose newest chain in the packs is neither on the node nor known asleep: {id, gen}
  defp lost do
    Ledger.packs()
    |> Enum.flat_map(fn {_, es} -> Ledger.chains(es) end)
    |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
    |> Enum.map(fn {id, gens} -> {id, Enum.max(gens)} end)
    |> Enum.reject(fn {id, gen} ->
      Ledger.gen(id) != nil or File.exists?(path(id)) or (Ledger.slept(id) || -1) >= gen
    end)
  end

  defp path(id), do: Path.join(Litestream.computers_dir(), id <> ".sqlite")

  defp recover({id, gen}) do
    Lock.locked(id, :infinity, fn ->
      case Objects.get(Objects.computer_key(id)) do
        {:ok, body} ->
          if Snapshot.gen_of(body) >= gen,
            do: asleep(id, Snapshot.gen_of(body)),
            else: rebuild(id, gen)

        :not_found ->
          rebuild(id, gen)

        {:error, why} ->
          {:failed, id, why}
      end
    end)
  end

  defp asleep(id, gen) do
    Ledger.put_slept(id, gen)
    {:asleep, id}
  end

  @doc "Computer `id`'s chain `gen` from every pack holding it, one ranged GET each, checked: `{:ok, %{name => bytes}}`."
  def segments(id, gen) do
    spans = for {name, es} <- Ledger.packs(), span = Pack.span(es, id, gen), do: {name, es, span}

    chunks =
      spans
      |> Task.async_stream(
        fn {name, es, {from, to}} ->
          with {:ok, bytes} <- Objects.pack_get(name, {from, to}),
               do: Pack.take(es, id, gen, bytes, from)
        end,
        timeout: 120_000,
        max_concurrency: Application.get_env(:moss, :restore_concurrency, 16)
      )
      |> Enum.reduce_while({:ok, []}, fn
        {:ok, {:ok, cs}}, {:ok, acc} -> {:cont, {:ok, cs ++ acc}}
        {:ok, other}, _ -> {:halt, {:error, other}}
      end)

    with {:ok, cs} <- chunks, do: Pack.join(cs)
  end

  defp rebuild(id, gen) do
    out = Path.join([Litestream.replica_root(), ".recover", id <> ".sqlite"])

    with {:ok, segments} <- segments(id, gen),
         :ok <- Litestream.rebuild(segments, out),
         {:ok, body} <- File.read(out),
         :ok <- Objects.put(Objects.computer_key(id), body) do
      asleep(id, max(Snapshot.gen_of(body), gen))
      {:rebuilt, id}
    else
      e ->
        Logger.warning("computer #{id} not rebuilt from its packs: #{inspect(e)}")
        {:failed, id, e}
    end
  after
    File.rm(Path.join([Litestream.replica_root(), ".recover", id <> ".sqlite"]))
  end
end

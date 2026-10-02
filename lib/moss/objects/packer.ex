defmodule Moss.Objects.Packer do
  @moduledoc """
  The node's packs (Arock PROJECT.md §15 item 4). Every `pack_ms` (a minute on
  a node) it gathers every awake computer's new segments, the ones Litestream
  wrote to the node's replica since the last pack, into one pack
  (`Moss.Objects.Pack`) and puts it with one request under the node's own
  prefix: one object a minute however many computers work, none when none do.
  A round with more than `pack_bytes` (64 MiB; the service takes up to 96) of segments writes as many
  packs as that takes.

  A computer's segments are read and its record (`Moss.Objects.Ledger`) is
  updated under its lock, held until the pack is up; a computer whose lock
  another holds (waking, sleeping) waits for the next round. A pack that
  fails to go up marks nothing, so the next round sends it all again.

  After each round it collects garbage: a pack every computer in it has
  outgrown (its snapshot is of that chain or a later one) is deleted, for
  free. A sleeping computer is kept whole (`Moss.Objects.Snapshot`), so packs
  matter only when the node loses its disk (`Moss.Objects.Recover`, run when
  the packer starts, before anything wakes).

  Only the node that runs Litestream runs the rounds; a mix task beside it
  (`litestream_run: false`) starts none.
  """
  use GenServer
  require Logger
  alias Moss.{Litestream, Objects}
  alias Moss.Objects.{Ledger, Lock, Pack, Recover}

  @pack_bytes 64 * 1024 * 1024

  def start_link(opts \\ []), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "A round now: `{:ok, %{packs: n, computers: n, bytes: n, deleted: n}}` or `{:error, why}`."
  def pack, do: GenServer.call(__MODULE__, :round, :infinity)

  @impl true
  def init(_opts) do
    if Application.get_env(:moss, :litestream_run, true) do
      case Recover.run() do
        {:ok, _} ->
          schedule()
          {:ok, %{}}

        {:error, why} ->
          {:stop, "the node's packs could not be read, so nothing may wake: #{inspect(why)}"}
      end
    else
      :ignore
    end
  end

  defp schedule,
    do: Process.send_after(self(), :round, Application.get_env(:moss, :pack_ms) || 60_000)

  @impl true
  def handle_call(:round, _from, state), do: {:reply, round(), state}

  @impl true
  def handle_info(:round, state) do
    with {:error, why} <- round(), do: Logger.warning("pack not put: #{inspect(why)}")
    schedule()
    {:noreply, state}
  end

  # -- a round -------------------------------------------------------------------------------------

  defp round do
    awake = gather(ids())

    result =
      try do
        files = for {_, c} <- awake, f <- c.files, do: f
        cap = Application.get_env(:moss, :pack_bytes, @pack_bytes)
        {put, failed} = put_all(Pack.plan(files, cap), [])
        ends = ends(put)

        # what is in packs now, of the segments still on the node (one Litestream removed never comes back)
        for {id, c} <- awake do
          up =
            for f <- c.files,
                ends[{id, f.name}] == byte_size(f.body),
                into: %{},
                do: {f.name, byte_size(f.body)}

          packed = c.packed |> Map.merge(up) |> Map.take(c.local)
          if packed != c.packed, do: Ledger.put_gen(id, c.gen, packed)
        end

        stats = %{
          packs: length(put),
          computers: map_size(Map.new(files, &{&1.id, true})),
          bytes: Enum.sum(Enum.map(files, &byte_size(&1.body)))
        }

        if failed, do: {:error, failed}, else: {:ok, stats}
      after
        for {id, _} <- awake, do: Lock.release(id)
      end

    deleted = collect()
    with {:ok, stats} <- result, do: {:ok, Map.put(stats, :deleted, deleted)}
  end

  # every computer in the replica that is awake on this node and not held by another, its lock taken
  defp ids do
    for d <- Path.wildcard(Path.join(Litestream.replica_root(), "*.sqlite")),
        id = Path.basename(d, ".sqlite"),
        Moss.Computer.id?(id),
        do: id
  end

  defp gather(ids) do
    Enum.flat_map(ids, fn id ->
      with :ok <- Lock.take(id, 0),
           %{"gen" => gen, "packed" => packed} <- Ledger.gen(id) do
        {local, files} = segments(id, gen, packed)
        [{id, %{gen: gen, packed: packed, local: local, files: files}}]
      else
        :busy -> []
        nil -> tap([], fn _ -> Lock.release(id) end)
      end
    end)
  end

  # the computer's segments on the node, and the new ones read: those not in a pack yet
  defp segments(id, gen, packed) do
    dir = Path.join(Litestream.replica_dir(id), "ltx")

    local =
      for f <- Path.wildcard(Path.join(dir, "*/*.ltx")),
          name = Path.relative_to(f, dir),
          Objects.segment?(name),
          {:ok, %{size: size}} <- [File.stat(f)],
          into: %{},
          do: {name, size}

    files =
      for {name, size} <- local,
          packed[name] != size,
          # compacted away between the listing and the read: nothing to keep
          {:ok, body} <- [File.read(Path.join(dir, name))],
          do: %{id: id, gen: gen, name: name, body: body}

    {Map.keys(local), files}
  end

  # packs up in order, stopping at the first that fails
  defp put_all([], put), do: {Enum.reverse(put), nil}

  defp put_all([chunks | rest], put) do
    name = Pack.name()
    {bytes, entries} = Pack.encode(chunks)

    case Objects.pack_put(name, bytes) do
      :ok ->
        Ledger.put_pack(name, entries)
        put_all(rest, [chunks | put])

      {:error, why} ->
        {Enum.reverse(put), why}
    end
  end

  # how far up each file went: its last chunk in a pack that went up (a file is in when that is its size)
  defp ends(put) do
    for pack <- put, c <- pack, reduce: %{} do
      acc ->
        Map.update(
          acc,
          {c.id, c.name},
          c.at + byte_size(c.body),
          &max(&1, c.at + byte_size(c.body))
        )
    end
  end

  # -- garbage ---------------------------------------------------------------------------------------

  @doc """
  Deletes every pack whose computers all slept on a later chain than the
  pack holds, and forgets the sleeps no pack needs any more. The number deleted.
  """
  def collect do
    packs = Ledger.packs()

    deleted =
      for {name, entries} <- packs, Ledger.garbage?(entries), Objects.pack_delete(name) == :ok do
        Ledger.drop_pack(name)
        name
      end

    needed =
      for {name, es} <- packs,
          name not in deleted,
          {id, _} <- Ledger.chains(es),
          into: MapSet.new(),
          do: id

    for id <- Ledger.slept_ids(), not MapSet.member?(needed, id), do: Ledger.drop_slept(id)
    length(deleted)
  end
end

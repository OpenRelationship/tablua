defmodule Moss.Objects.Pack do
  @moduledoc """
  A pack: one object holding many awake computers' new Litestream segments,
  so a node writes one object a minute however many computers work (Arock
  PROJECT.md §15 item 4). Pure: no files, no store.

      <<"MOSSPACK", 1, header_length::32>> <> header_json <> bytes

  The header lists entries, each a byte range of one segment file of one
  computer's chain: `id`, `gen` (the chain: a computer's wake from its
  snapshot), `name` (`<level>/<min>-<max>.ltx`), `at` and `size` (where the
  range sits in the file, and the file's whole size; a file larger than a
  pack is split across packs), `offset` and `length` (where it sits in the
  pack) and `crc` (CRC-32 of the range). Entries are sorted by computer, so one
  computer's entries are one contiguous range of the pack, read with one
  ranged GET. Decoded, `offset` counts from the pack's first byte.
  """

  @magic "MOSSPACK"
  @version 1
  @lead 13

  @doc "A new pack's name: its time in milliseconds (16 hex digits) and a random tag (8)."
  def name(ms \\ System.os_time(:millisecond)) do
    time = String.downcase(String.pad_leading(Integer.to_string(ms, 16), 16, "0"))
    time <> "-" <> Base.encode16(:crypto.strong_rand_bytes(4), case: :lower) <> ".pack"
  end

  @doc "Whether `name` is a pack's name, as the service checks it."
  def name?(name),
    do: is_binary(name) and Regex.match?(~r/\A[0-9a-f]{16}-[0-9a-f]{8}\.pack\z/, name)

  @doc """
  Splits files (`%{id, gen, name, body}`) into packs of at most `cap` bytes of
  segments each, a file larger than the room left going on in the next: a
  list of packs, each a list of chunks (`%{id, gen, name, at, size, body}`).
  """
  def plan(files, cap) when cap > 0 do
    {packs, cur, _} =
      files
      |> Enum.sort_by(&{&1.id, &1.name})
      |> Enum.reduce({[], [], cap}, &split(&1, 0, &2, cap))

    Enum.reverse([Enum.reverse(cur) | packs]) |> Enum.reject(&(&1 == []))
  end

  defp split(f, at, {packs, cur, room}, cap) do
    left = byte_size(f.body) - at

    cond do
      left <= room ->
        {packs, [chunk(f, at, left) | cur], room - left}

      room == 0 ->
        split(f, at, {[Enum.reverse(cur) | packs], [], cap}, cap)

      true ->
        split(f, at + room, {[Enum.reverse([chunk(f, at, room) | cur]) | packs], [], cap}, cap)
    end
  end

  defp chunk(f, at, n),
    do: %{
      id: f.id,
      gen: f.gen,
      name: f.name,
      at: at,
      size: byte_size(f.body),
      body: binary_part(f.body, at, n)
    }

  @doc "A pack of `chunks`: `{bytes, entries}`, the entries as `header/1` decodes them."
  def encode(chunks) do
    sorted = Enum.sort_by(chunks, &{&1.id, &1.gen, &1.name, &1.at})

    {entries, _} =
      Enum.map_reduce(sorted, 0, fn c, offset ->
        n = byte_size(c.body)

        {%{
           "id" => c.id,
           "gen" => c.gen,
           "name" => c.name,
           "at" => c.at,
           "size" => c.size,
           "offset" => offset,
           "length" => n,
           "crc" => :erlang.crc32(c.body)
         }, offset + n}
      end)

    json = Jason.encode!(%{"version" => @version, "entries" => entries})

    bytes =
      IO.iodata_to_binary([
        @magic,
        <<@version, byte_size(json)::32>>,
        json | Enum.map(sorted, & &1.body)
      ])

    {bytes, absolute(entries, @lead + byte_size(json))}
  end

  @doc "How many bytes from the start hold the header: `{:ok, n}`, `:short` (read more first) or `{:error, why}`."
  def header_size(<<@magic, @version, len::32, _::binary>>), do: {:ok, @lead + len}
  def header_size(bin) when byte_size(bin) < @lead, do: :short
  def header_size(_), do: {:error, "not a pack"}

  @doc "The entries of a pack, from bytes holding at least its header."
  def header(bin) do
    with {:ok, n} <- header_size(bin),
         true <- byte_size(bin) >= n || {:error, "the header is cut short"},
         {:ok, %{"version" => @version, "entries" => entries}} <-
           Jason.decode(binary_part(bin, @lead, n - @lead)) do
      {:ok, absolute(entries, n)}
    else
      {:ok, _} -> {:error, "not a pack's header"}
      {:error, %Jason.DecodeError{}} -> {:error, "not a pack's header"}
      other -> other
    end
  end

  defp absolute(entries, data_at),
    do: Enum.map(entries, &Map.update!(&1, "offset", fn o -> o + data_at end))

  @doc "The byte range (first and last, inclusive) of computer `id`'s chain `gen` in a pack, or nil."
  def span(entries, id, gen) do
    case for(e <- entries, e["id"] == id and e["gen"] == gen, do: e) do
      [] -> nil
      es -> {hd(es)["offset"], Enum.max(Enum.map(es, &(&1["offset"] + &1["length"]))) - 1}
    end
  end

  @doc """
  Computer `id`'s chunks of chain `gen` from `bytes`, the pack's bytes from
  offset `from` (a span's), each checked against its CRC: `{:ok, chunks}`.
  """
  def take(entries, id, gen, bytes, from) do
    Enum.reduce_while(entries, {:ok, []}, fn
      %{"id" => ^id, "gen" => ^gen} = e, {:ok, acc} ->
        at = e["offset"] - from

        with true <- at >= 0 and at + e["length"] <= byte_size(bytes),
             body = binary_part(bytes, at, e["length"]),
             true <- :erlang.crc32(body) == e["crc"] do
          {:cont, {:ok, [%{name: e["name"], at: e["at"], size: e["size"], body: body} | acc]}}
        else
          _ -> {:halt, {:error, "#{id}'s #{e["name"]} at #{e["at"]} does not match its checksum"}}
        end

      _, acc ->
        {:cont, acc}
    end)
  end

  @doc "Whole files from chunks (from any packs, repeats allowed): `{:ok, %{name => body}}`, or an error naming a gap."
  def join(chunks) do
    chunks
    |> Enum.group_by(& &1.name)
    |> Enum.reduce_while({:ok, %{}}, fn {name, cs}, {:ok, acc} ->
      parts = cs |> Enum.uniq_by(& &1.at) |> Enum.sort_by(& &1.at)
      body = IO.iodata_to_binary(Enum.map(parts, & &1.body))

      contiguous =
        Enum.reduce(parts, 0, fn c, at -> if c.at == at, do: at + byte_size(c.body), else: -1 end)

      if contiguous == hd(parts).size and byte_size(body) == hd(parts).size,
        do: {:cont, {:ok, Map.put(acc, name, body)}},
        else: {:halt, {:error, "#{name} is missing part of its bytes"}}
    end)
  end
end

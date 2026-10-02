defmodule Moss.PackTest do
  # Arock's PROJECT.md §15 item 4: a pack holds many computers' segments behind a header, each computer's entries
  # one contiguous range, each range checked by its CRC, and a file larger than a pack split across packs.
  use ExUnit.Case, async: true

  alias Moss.Objects.Pack

  defp file(id, gen, name, body), do: %{id: id, gen: gen, name: name, body: body}

  test "a pack's name is its time and a random tag, and nothing else is one" do
    name = Pack.name(1_790_886_016_733)
    assert name =~ ~r/\A000001a0f91ff6dd-[0-9a-f]{8}\.pack\z/
    assert Pack.name?(name)
    refute Pack.name?("0000019a2b3c4d5e.pack")
    refute Pack.name?("../x-00000000.pack")
    refute Pack.name?(name <> ".tmp")
  end

  test "the header reads back every entry, and each computer's entries are one range" do
    files = [
      file("rock-b", 1, "0/0000000000000001-0000000000000001.ltx", "bbb"),
      file("rock-a", 3, "0/0000000000000001-0000000000000001.ltx", "first"),
      file("rock-a", 3, "1/0000000000000001-0000000000000002.ltx", "second")
    ]

    [chunks] = Pack.plan(files, 1_000)
    {bytes, entries} = Pack.encode(chunks)
    assert {:ok, ^entries} = Pack.header(bytes)
    assert Enum.map(entries, & &1["id"]) == ["rock-a", "rock-a", "rock-b"]

    {from, to} = Pack.span(entries, "rock-a", 3)
    assert binary_part(bytes, from, to - from + 1) == "firstsecond"

    assert {:ok, chunks} =
             Pack.take(entries, "rock-a", 3, binary_part(bytes, from, to - from + 1), from)

    assert {:ok,
            %{
              "0/0000000000000001-0000000000000001.ltx" => "first",
              "1/0000000000000001-0000000000000002.ltx" => "second"
            }} =
             Pack.join(chunks)

    assert Pack.span(entries, "rock-a", 2) == nil
  end

  test "a header is read from the pack's first bytes, asking for more when they are too few" do
    {bytes, entries} = Pack.encode(hd(Pack.plan([file("rock-a", 1, "0/x.ltx", "x")], 10)))
    assert Pack.header_size(binary_part(bytes, 0, 5)) == :short
    assert {:ok, n} = Pack.header_size(binary_part(bytes, 0, 13))
    assert {:ok, ^entries} = Pack.header(binary_part(bytes, 0, n))
    assert {:error, _} = Pack.header(binary_part(bytes, 0, n - 1))
    assert {:error, _} = Pack.header("SQLite format 3\0 and the rest")
  end

  test "a range whose bytes changed is refused by its checksum" do
    {bytes, entries} =
      Pack.encode(hd(Pack.plan([file("rock-a", 1, "0/x.ltx", "good bytes")], 100)))

    {from, to} = Pack.span(entries, "rock-a", 1)
    bad = binary_part(bytes, from, to - from) <> "X"
    assert {:error, why} = Pack.take(entries, "rock-a", 1, bad, from)
    assert why =~ "checksum"
  end

  test "a file larger than a pack goes on across packs and joins back whole; one part missing is a gap" do
    big = :crypto.strong_rand_bytes(25)

    packs =
      Pack.plan([file("rock-a", 1, "0/a.ltx", "1234567"), file("rock-a", 1, "0/b.ltx", big)], 10)

    assert Enum.map(packs, fn p -> Enum.sum(Enum.map(p, &byte_size(&1.body))) end) == [
             10,
             10,
             10,
             2
           ]

    chunks =
      for p <- packs,
          {bytes, entries} = Pack.encode(p),
          {from, to} = Pack.span(entries, "rock-a", 1) do
        {:ok, cs} = Pack.take(entries, "rock-a", 1, binary_part(bytes, from, to - from + 1), from)
        cs
      end

    all = List.flatten(chunks)
    assert {:ok, %{"0/a.ltx" => "1234567", "0/b.ltx" => ^big}} = Pack.join(all ++ all)
    assert {:error, _} = Pack.join(Enum.reject(all, &(&1.name == "0/b.ltx" and &1.at == 3)))
  end
end

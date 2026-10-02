defmodule Moss.LogRecallTest do
  # Arock's PROJECT.md §14.7 item 9: SQLite may store and compare an agent's bytes as bound values; it never
  # parses them. Moss's hot path writes arock-log's recall index from Elixir, so it is held here to arock-log's own Lua:
  # the tokenizer to arock-log's vectors, what append writes to arock-log's append and to arock-log's index of the whole log,
  # and Moss's search to arock-log's ranking, score for score.
  use ExUnit.Case, async: true

  alias Moss.{Db, Log}
  alias Moss.Log.{Recall, Search, Tokens}

  @moduletag :tmp_dir

  defp lua(code, ports \\ []) do
    lua = Moss.Lua.Ports.bind(Moss.Lua.base(), ports)
    {[v], lua} = Lua.eval!(lua, code)
    decode(Moss.Lua.decode(lua, v))
  end

  # a decoded Lua list (keys 1..n) as a list, an empty table as []
  defp decode([]), do: []

  defp decode([{k, _} | _] = pairs) when is_integer(k),
    do: pairs |> Enum.sort() |> Enum.map(&decode(elem(&1, 1)))

  defp decode([{_, _} | _] = pairs), do: Map.new(pairs, fn {k, v} -> {k, decode(v)} end)
  defp decode(v), do: v

  defp db(dir, name) do
    {:ok, conn} = Db.open(Path.join(dir, name <> ".sqlite"))
    :ok = Log.open(conn)
    conn
  end

  defp dump(conn) do
    {:ok, [d]} = Log.alog(conn, "dump", [])
    d
  end

  test "the tokenizer gives every one of arock-log's vectors, and arock-log's limits" do
    vectors = lua("return require('arock-log.tokens_vectors')")
    assert length(vectors) > 20

    for [text, want] <- vectors do
      assert Tokens.tokens(text) == want, "tokens of #{inspect(text, limit: 40)}"
    end

    assert {lua("return require('arock-log').TOKEN_BYTES"), lua("return require('arock-log').TOKENS")} ==
             Tokens.limits()
  end

  test "the tokenizer agrees with arock-log's on random bytes" do
    alphabet = ~c"aZ09 -_/.\t\n" ++ [0, 127, 128, 195, 169, 226, 255]

    for _ <- 1..200 do
      text = for _ <- 1..:rand.uniform(120), into: "", do: <<Enum.random(alphabet)>>
      text = if :rand.uniform(4) == 1, do: text <> String.duplicate("Ab", 40), else: text

      want =
        lua(
          "return require('arock-log.tokens').tokens(...)"
          |> String.replace("...", inspect_lua(text))
        )

      assert Tokens.tokens(text) == want, "tokens of #{inspect(text)}"
    end
  end

  # a Lua string literal of any bytes
  defp inspect_lua(s),
    do: "\"" <> for(<<c <- s>>, into: "", do: "\\" <> Integer.to_string(c)) <> "\""

  # Every path append takes: folders, a text written twice and a blob shared, binary content, UTF-8, a text
  # past 64 KB and 10,000 tokens, an empty file, runs, requests, post, a folder moved over its own prefix
  # neighbours, a file moved onto another, and deletes of a file and of a folder.
  @big Enum.map_join(1..12_000, " ", &"Word#{rem(&1, 1500)}")
  @events [
    {"Make Folder", ["/"], "host"},
    {"Make Folder", ["/home"], "host"},
    {"Make Folder", ["/home/docs"], "agent"},
    {"Write File", ["/home/docs/a.txt", "The Quokka sleeps under the FERN, the fern."], "agent"},
    {"Write File", ["/home/docs/b.txt", "The Quokka sleeps under the FERN, the fern."], "agent"},
    {"Write File", ["/home/docs/bin.dat", <<0, 1, 2, "abc quokka">>], "agent"},
    {"Write File", ["/home/café/naïve—Notes.md", "Crème brûlée, CAFÉ naïve quokka"], "agent"},
    {"Run Command", ["ls -la /home/docs", "/home", "0", "1.500", "a.txt\nb.txt\n", ""], "agent"},
    {"Write File", ["/home/docs/a.txt", "now the moss grows over the stones"], "agent"},
    {"Write File", ["/home/big.txt", @big], "agent"},
    {"Write File", ["/home/empty.txt", ""], "agent"},
    {"Write File", ["/home/docs-x.txt", "a neighbour before the folder: quokka"], "agent"},
    {"Write File", ["/home/docs0.txt", "a neighbour after the folder"], "agent"},
    {"Move File", ["/home/docs", "/home/papers"], "agent"},
    {"Write File", ["/home/x.txt", "x marks the fern"], "agent"},
    {"Move File", ["/home/x.txt", "/home/papers/b.txt"], "agent"},
    {"Serve Request", ["POST", "/add", "200", "3.2", "name=fern", "<p>hi fern</p>"], "user"},
    {"Send Mail", ["moss-2", "Ferns", "water the fern", "delivered", "7"], "agent"},
    {"Receive Mail", ["moss-2", "Re: Ferns", "watered", "8"], "host"},
    {"Delete File", ["/home/papers/bin.dat"], "agent"},
    {"Delete File", ["/home/café"], "agent"},
    {"Write File", ["/home/papers/bin.dat", "text again where binary was"], "agent"}
  ]

  @queries [
    "quokka",
    "fern papers",
    "TXT",
    "naïve café",
    "ls home",
    "Receive Mail",
    "word7 word1499",
    "nothing here",
    "",
    "moss stones x"
  ]

  test "append writes what arock-log's append writes, and what alog indexes from the log", %{
    tmp_dir: dir
  } do
    moss = db(dir, "moss")
    ref = db(dir, "alog")

    for {keyword, args, actor} <- @events do
      assert :ok = Log.append(moss, "t1", keyword, args, actor)
      assert {:ok, _} = Log.alog(ref, "append", ["t1", keyword, args, actor])
    end

    want = dump(ref)
    assert dump(moss) == want
    assert_search(moss, ref)

    # packed into blocks: the same index, the same answers
    {:ok, [%{"n" => pending}]} = Db.exec(moss, "select count(*) as n from recall_pending", [])
    assert pending > 2_000
    {:ok, _} = Db.exec(moss, Recall.alog().flush_sql, [])
    assert dump(moss) == want
    assert_search(moss, ref)

    # arock-log's rebuild, and arock-log's index of the whole log at a new version
    {:ok, _} = Log.alog(moss, "rebuild", [])
    assert dump(moss) == want
    {:ok, _} = Db.exec(moss, "update alog_state set version = 0", [])
    :ok = Log.open(moss)
    assert dump(moss) == want
    assert_search(moss, ref)

    # and appends go on after it
    assert :ok = Log.append(moss, "t1", "Delete File", ["/home/papers"], "agent")
    {:ok, _} = Log.alog(ref, "append", ["t1", "Delete File", ["/home/papers"], "agent"])
    assert dump(moss) == dump(ref)

    {:ok, paths} = Db.exec(moss, "select path from files where dir = 0 order by path", [])

    assert Enum.map(paths, & &1["path"]) ==
             ~w(/home/big.txt /home/docs-x.txt /home/docs0.txt /home/empty.txt)
  end

  test "a failed append leaves nothing of itself, recall included", %{tmp_dir: dir} do
    conn = db(dir, "fail")
    :ok = Log.append(conn, "t1", "Make Folder", ["/home"], "host")
    before = dump(conn)
    # a file over a folder's path breaks files' primary key mid-move
    :ok = Log.append(conn, "t1", "Write File", ["/home/a/x", "one quokka"], "agent")
    :ok = Log.append(conn, "t1", "Make Folder", ["/home/b"], "agent")
    :ok = Log.append(conn, "t1", "Write File", ["/home/b/x", "two"], "agent")
    mid = dump(conn)
    refute mid == before
    assert {:error, _} = Log.append(conn, "t1", "Move File", ["/home/a", "/home/b"], "agent")
    assert dump(conn) == mid
    {:ok, [%{"n" => 4}]} = Db.exec(conn, "select count(*) as n from events", [])
  end

  # Moss's search against recall.lua's own, scores included
  defp assert_search(moss, ref) do
    for q <- @queries, {fun, key} <- [events: "seq", files: "path"] do
      code = "return require('arock-log.recall').#{fun}(arock.host().db, #{inspect_lua(q)}, 10)"
      want = for h <- lua(code, db: ref), do: {h[key], h["score"]}
      got = apply(Search, fun, [moss, q, 10])

      assert Enum.map(got, &elem(&1, 0)) == Enum.map(want, &elem(&1, 0)),
             "#{fun} of #{inspect(q)}"

      for {{_, a}, {_, b}} <- Enum.zip(got, want),
          do: assert_in_delta(a, b, 1.0e-12, "#{fun} of #{inspect(q)}")
    end

    assert %{events: [_ | _], files: [_ | _]} = Search.recall(moss, "quokka")
  end
end

defmodule Moss.GuardTest do
  # No C an agent can reach (Arock PROJECT.md §14.7 item 9): the BEAM is the computer's microVM and Lua its
  # boundary, so what an agent controls (its Lua, its SQL, its pages, the web it fetches) is handled by Erlang
  # and Elixir only. These tests fail the build when that stops being true: a native library appears, a module
  # outside the host's own storage reaches SQLite, agent text becomes atoms, or a term is decoded from bytes an
  # agent could have written. Each allowance below says why it is safe; adding one is a reviewed change.
  use ExUnit.Case, async: false

  alias Moss.Computer

  @lib Path.expand("../../lib", __DIR__)

  # native libraries in the build, and why each is out of an agent's reach
  @native %{
    "exqlite" =>
      "SQLite, for the host's own storage only: fixed statements, an agent's bytes only as bound values " <>
        "(its SQL runs in Moss.Sql, and a trace test holds that)",
    "lazy_html" =>
      "test-only (Phoenix.LiveViewTest needs it; cleaner tests use it as an independent check)",
    "wasmex" =>
      "moss-browser's look only (Arock PROJECT.md §16.3): one pinned module, run in a node of its own " <>
        "(MossBrowser.Look.Node over :peer), never in this one, and no Moss source calls it"
  }

  # the only files that may call SQLite, each running statements written here, never an agent's
  @sqlite_callers %{
    "lib/moss/db.ex" => "the connection itself",
    "lib/moss/computer/disk.ex" => "a computer's file: fixed statements, its bytes bound",
    "lib/moss/computer/session.ex" =>
      "the computer's kept session: two fixed statements, the term bound",
    "lib/moss/log.ex" => "arock-log's hot path: fixed statements, an event's arguments bound",
    "lib/moss/log/recall.ex" =>
      "arock-log's recall index on the hot path: fixed statements (two literal subqueries for the document), " <>
        "every token and path bound",
    "lib/moss/log/search.ex" => "recall search: fixed statements, the query's tokens bound",
    "lib/moss/lua/ports.ex" =>
      "arock-log's own Lua (Moss.Log), in a state no agent script gets; arock-log's SQL is fixed",
    "lib/moss/sql/store.ex" =>
      "an agent database's rows, by fixed statements; its SQL runs in Moss.Sql",
    "lib/moss/computer.ex" => "the post's delivery query, fixed",
    "lib/moss/owners.ex" => "who owns which computer, fixed statements",
    "lib/moss/names.ex" =>
      "the node's org: names: fixed statements, every address and name bound (a manifest is read by arock-log's Lua)",
    "lib/moss/mail/store.ex" =>
      "the post: fixed statements, and `set` names only its known columns",
    "lib/moss/computer/tabula.ex" =>
      "the agent harness's own tables: every statement checked to name only tabula_ tables, its values bound",
    "lib/moss/computer/experience.ex" =>
      "the node's shared experience: fixed statements, every row's computer, task, keyword and arguments bound"
  }

  # the only terms decoded from bytes: encoded by the host itself, into a place no agent writes, and decoded
  # with [:safe], which never makes an atom
  @decoders %{
    "lib/moss/computer/session.ex" =>
      "a computer's kept session, which only the host writes to its file"
  }

  test "the build holds no native library but those allowed, and the C parser is test-only" do
    found =
      for so <- Path.wildcard(Path.join(Mix.Project.build_path(), "lib/*/priv/**/*.so")),
          into: MapSet.new(),
          do:
            so
            |> Path.relative_to(Path.join(Mix.Project.build_path(), "lib"))
            |> Path.split()
            |> hd()

    assert MapSet.subset?(found, MapSet.new(Map.keys(@native))),
           "native code not allowed: #{inspect(MapSet.difference(found, MapSet.new(Map.keys(@native))))}"

    lazy = Enum.find(Mix.Project.config()[:deps], &(elem(&1, 0) == :lazy_html))
    assert lazy && Keyword.get(elem(lazy, tuple_size(lazy) - 1), :only) == :test
    assert sources_with(~r/\bLazyHTML\b/) == [], "LazyHTML is used outside tests"
    assert sources_with(~r/\bWasmex\b/) == [], "Moss calls wasmex itself: only moss-browser's look node may"
  end

  test "only the host's own storage reaches SQLite" do
    assert sources_with(
             ~r/\bExqlite\b|\bMoss\.Db\.(exec|query|prepare)|\bDb\.(exec|query|prepare)\b/
           ) --
             Map.keys(@sqlite_callers) == []
  end

  test "no text becomes an atom, and only the host's own bytes are decoded, safely" do
    assert sources_with(~r/String\.to_atom|binary_to_atom|list_to_atom/) == []

    decoders = sources_with(~r/binary_to_term/)
    assert decoders -- Map.keys(@decoders) == []

    for f <- decoders,
        line <- String.split(File.read!(Path.join(@lib, "../" <> f)), "\n"),
        line =~ "binary_to_term",
        do: assert(line =~ "[:safe]", "#{f}: #{String.trim(line)}")
  end

  # The same kinds of input twice: once to load what first use loads, then with names never seen. Shell words,
  # environment names, paths, JSON keys, Lua table keys and modules, SQL names, HTML tags and attributes.
  test "nothing an agent sends makes a new atom" do
    id = "guard-#{System.unique_integer([:positive])}"
    battery(id, "warm")
    before = :erlang.system_info(:atom_count)
    for n <- 1..3, do: battery(id, "x#{System.unique_integer([:positive])}n#{n}")
    assert :erlang.system_info(:atom_count) == before
  end

  defp battery(id, w) do
    Computer.run(
      id,
      "echo #{w} && export V_#{w}=#{w} && mkdir -p /home/#{w} && cd /home/#{w} && ls"
    )

    Computer.exec(id, %{
      "cwd" => "/home",
      "cmd" => "lua #{w}.lua",
      "files" => %{
        "#{w}.lua" => """
        local t = json.decode('{"k_#{w}": {"#{w}": [1, "#{w}"]}}')
        local u = { ["#{w}"] = t, #{w} = true }
        pcall(require, "mod_#{w}")
        local d = db.open("data/#{w}.dbl")
        d:exec("create table t_#{w} (c_#{w} text, n_#{w} integer)")
        d:exec("insert into t_#{w} values (?, ?)", "#{w}", 1)
        d:query("select c_#{w} as a_#{w} from t_#{w} where n_#{w} = 1")
        pcall(function() d:exec("select nope_#{w}() from t_#{w}") end)
        d:close()
        print(json.encode(u))
        """
      }
    })

    html =
      ~s(<x-#{w} a-#{w}="1" on#{w}="x" data-#{w}="2"><#{w}>t</#{w}><svg><#{w}-g k#{w}="v"/></svg></x-#{w}>)

    Moss.Computer.Clean.html("<!doctype html><html><body>" <> html <> "</body></html>")
    MossBrowser.HTML.parse(html)
    MossBrowser.Page.new("http://example.test/#{w}", html)
  end

  # Arock's feature file-kinds, goal 10: what the kinds replaced is gone, from the code and the help alike
  test "no old path remains: no app.lua, no long help, no JSON tasks" do
    shroomi =
      Path.expand("../../submodules/shroomi", Path.expand("..", @lib) |> Path.join("../.."))

    rockmail = Path.join(Path.dirname(shroomi), "uspx")

    files =
      Path.wildcard(Path.join(@lib, "**/*.ex")) ++
        Path.wildcard(Path.join(Path.expand("../priv", @lib), "**/*.lua")) ++
        Path.wildcard(Path.join(shroomi, "*.lua")) ++ Path.wildcard(Path.join(rockmail, "*.lua"))

    assert length(files) > 50

    for f <- files,
        old <- [
          "/home/app.lua",
          "app.lua",
          "help shroomi",
          "shroomi_reference",
          "tasks.new",
          "tasks.parse",
          # arock-mail's (now uspx's) JSON task subject marker, quoted as the code wrote it
          ~s("task: ")
        ],
        do: refute(File.read!(f) =~ old, "#{Path.basename(f)} still says #{old}")
  end

  defp sources_with(re) do
    for f <- Path.wildcard(Path.join(@lib, "**/*.ex")),
        File.read!(f) =~ re,
        do: Path.relative_to(f, Path.expand("..", @lib))
  end
end

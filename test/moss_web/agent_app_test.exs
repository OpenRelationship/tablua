defmodule MossWeb.AgentAppTest do
  # Shroomi's check 5 (Arock PROJECT.md §16.1): a model given only its computer, and `help page` there, builds a
  # working app, looks at it with its own browser (`open app`), and the app then does what was asked when its
  # person uses it. Live, through Moss.AgentLoop: `mix test --only agent`; MOSS_AGENT_MODEL picks the model.
  use MossWeb.ConnCase, async: false

  alias Moss.Computer

  @moduletag :agent
  @moduletag timeout: 3_600_000

  setup_all do
    Moss.AgentLoop.own_folders()
    :ok
  end

  @task """
  You have your own computer, reached through the `computer` tool. It is not Linux: its commands are few (run
  `help`), and its one language is Lua. Run `help page` first: it is how you publish pages there.

  Make the computer's page, ui/index.lui (its person opens it in their browser): a reading list.

    - The page shows the books not yet read, then the ones read, and says "<n> to read" (e.g. "2 to read").
    - A form adds a book: a field named "title", sent to the page's action named add.
    - Each unread book has a button that marks it read: the action named read, with title = the book's title.
    - Books are kept in a database, so they are there the next time the page is opened.
    - It should look finished: use the kit's components, and run ui.check on your page until it names no class.

  Use your computer's browser to see the app as its person would (`open app`, then `type`, `click`), add a book
  and mark it read there, and fix what you find. When it works, answer with one word: DONE.
  """

  defp as, do: Plug.Test.init_test_session(build_conn(), person: "tester")

  test "an agent builds a page from help page, and it works for its person" do
    id = "agent-app-#{System.unique_integer([:positive])}"
    :ok = Moss.Owners.claim(id, "tester")

    {_turns, cmds} =
      Moss.AgentLoop.run(
        id,
        @task,
        "Keep going until the app works in `open app`, then answer DONE."
      )

    # it looked at its own app, and worked it
    assert Enum.any?(cmds, &(&1 =~ ~r/\bopen\s+app\b/)), "never opened its app"
    assert Enum.any?(cmds, &(&1 =~ ~r/\b(click|submit)\b/)), "never used its app"

    base = "/computers/#{id}/app/"
    hx = fn conn -> put_req_header(conn, "hx-request", "true") end

    # its person, starting from an empty list
    Computer.exec(id, %{"cwd" => "/home", "cmd" => "true"})
    page = html_response(get(as(), base), 200)
    assert page =~ ~s(name="title")
    assert page =~ ~s(hx-post="?do=add")

    for title <- ["Dune", "Middlemarch"],
        do:
          assert(
            post(hx.(as()), base <> "?do=add", %{"title" => title}).status in [200, 204, 303]
          )

    page = html_response(get(as(), base), 200)
    assert page =~ "Dune" and page =~ "Middlemarch"
    count = fn p -> Regex.run(~r/(\d+) to read/, p, capture: :all_but_first) end
    before = count.(page)
    assert before, "no \"<n> to read\" on the page"

    assert post(hx.(as()), base <> "?do=read", %{"title" => "Dune"}).status in [200, 204, 303]
    page = html_response(get(as(), base), 200)
    assert String.to_integer(hd(count.(page))) == String.to_integer(hd(before)) - 1

    # finished by Shroomi's own measure: no class it does not know
    unknown =
      Computer.exec(id, %{
        "cwd" => "/tmp",
        "cmd" =>
          ~s|lua -e 'print(table.concat(require("shroomi").check(fs.read("p.html")), " "))'|,
        "files" => %{"p.html" => page}
      })["stdout"]

    assert String.trim(unknown) == "", "classes Shroomi does not know: #{unknown}"
    IO.puts("\n" <> Computer.run(id, "cat /home/ui/index.lui").out)
  end
end

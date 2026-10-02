defmodule MossWeb.AppTest do
  # Apps the person opens (Arock PROJECT.md §14.7, goal 5): the computer serves its .lui pages as HTML and htmx, the
  # person's browser draws it, and the agent reads the same page as words and controls with its own browser.
  use MossWeb.ConnCase, async: false

  alias Moss.Computer
  alias Moss.Computer.Disk

  defp as(person), do: Plug.Test.init_test_session(build_conn(), person: person)
  defp cid, do: "app-#{System.unique_integer([:positive])}"

  defp put_file(c, path, text),
    do: :ok = Disk.write(:sys.get_state(Computer.wake!(c)).disk, path, text)

  @page ~S"""
  <lua>
    local d = db.open("data/plants.dbl")
    d:exec("create table if not exists plant (name text primary key)")
    page.title = "Plants"
    function post.add(req)
      d:exec("insert or ignore into plant values (?)", req.form.name)
      return { redirect = "./" }
    end
    function post.remove(req) d:exec("delete from plant where name = ?", req.form.name) end
    function get.boom() error("no such plant") end
  </lua>
  <h1>Plants</h1>
  <ul>
    {% for _, r in ipairs(d:query("select name from plant order by name")) do %}
      <li>{{ r.name }} <button post="remove" vals={{ {name = r.name} }}>Remove {{ r.name }}</button></li>
    {% end %}
  </ul>
  <form post="add"><input name="name" label="Name"/><button>Add</button></form>
  <a href="about">About</a>
  {{{ '<script>alert(1)</script><img src="x" onerror="alert(2)"><a href="javascript:alert(3)">x</a>' }}}
  """

  @about ~S"""
  <lua>page.title = "About"</lua>
  <p>A plant list, by an agent.</p>
  """

  defp put_app(c) do
    put_file(c, "/home/ui/index.lui", @page)
    put_file(c, "/home/ui/about.lui", @about)
  end

  test "the person opens the app: HTML with htmx, the agent's scripts unable to run" do
    c = cid()
    Moss.Owners.claim(c, "tester")
    put_app(c)

    assert redirected_to(get(as("tester"), "/computers/#{c}/app"), 302) == "/computers/#{c}/app/"

    conn = get(as("tester"), "/computers/#{c}/app/")
    assert html_response(conn, 200) =~ "<h1>Plants</h1>"
    body = conn.resp_body
    assert body =~ ~s(<base href="/computers/#{c}/app/">)
    assert body =~ ~s(<script src="/shroomi/htmx-2.0.4.min.js">)
    assert body =~ ~s(<link rel="stylesheet" href="/shroomi/basecoat-1.0.2.min.css"/>)
    refute body =~ "alert"
    refute body =~ "onerror"

    [csp] = get_resp_header(conn, "content-security-policy")

    assert csp =~
             "script-src http://www.example.com/shroomi/basecoat-1.0.2.min.js " <>
               "http://www.example.com/shroomi/htmx-2.0.4.min.js http://www.example.com/shroomi/idiomorph-0.7.3.min.js " <>
               "http://www.example.com/shroomi/shroomi.js;"

    assert csp =~ "connect-src http://www.example.com/computers/#{c}/app/;"
    refute csp =~ "unsafe-eval"
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]

    # htmx posts without a CSRF token, and the app's redirect stays inside it
    conn = post(as("tester"), "/computers/#{c}/app/?do=add", %{"name" => "fern"})
    assert redirected_to(conn, 303) == "http://www.example.com/computers/#{c}/app/"
    assert get(as("tester"), "/computers/#{c}/app/").resp_body =~ "<li>fern"

    # a path no page answers is not found, and a page's failures are its own
    assert get(as("tester"), "/computers/#{c}/app/script").status == 404
    conn = get(as("tester"), "/computers/#{c}/app/?do=boom")
    assert conn.status == 500 and conn.resp_body =~ "no such plant"

    # no one else reaches it
    assert get(as("other"), "/computers/#{c}/app/").status == 404
  end

  test "Shroomi's assets are served as pinned, each matching its hash in the policy" do
    for {file, "sha384-" <> hash} <- Moss.Computer.Clean.policy().files do
      conn = get(build_conn(), "/shroomi/" <> file)
      assert conn.status == 200, file
      assert :crypto.hash(:sha384, conn.resp_body) |> Base.encode64() == hash, file
    end

    assert get(build_conn(), "/shroomi/README.md").status == 404
  end

  test "the agent reads its app as words and controls, and works it with its own browser" do
    c = cid()
    put_app(c)

    assert %{code: 0, out: out} = Computer.run(c, "open app")
    assert out =~ "# Plants"
    refute out =~ "alert"
    assert out =~ ~s(field "Name")
    assert out =~ ~s(button "Add")
    assert out =~ ~s(link "About")

    assert %{code: 0} = Computer.run(c, "type Name moss")
    assert %{code: 0, out: out} = Computer.run(c, "click Add")
    assert out =~ "- moss"

    assert %{code: 0} = Computer.run(c, "type Name fern")
    assert %{code: 0} = Computer.run(c, "submit")
    assert %{code: 0, out: page} = Computer.run(c, "page")
    assert page =~ "- fern" and page =~ "- moss"

    assert %{code: 0, out: out} = Computer.run(c, ~s(click "Remove fern"))
    refute out =~ "- fern"
    assert out =~ "- moss"

    assert %{code: 0, out: out} = Computer.run(c, "click About")
    assert out =~ "A plant list, by an agent."

    put_file(c, "/home/ui/index.lui", "<lua>error('broken')</lua>")
    assert %{code: 22, err: err} = Computer.run(c, "open app")
    assert err =~ "500"
  end

  # what `help page` tells an agent about pages is how they work: each line it states, done here as written
  test "help page teaches pages and the browser, and what it says holds" do
    c = cid()
    assert %{code: 0, out: help} = Computer.run(c, "help page")

    for line <- [
          "apps/plants/ui/index.lui",
          ~s(post="water" names the page's action),
          "open app/plants",
          "click <id|words>"
        ],
        do: assert(help =~ line, line)

    refute help =~ "app.lua"
    assert Computer.run(c, "help click").out == Moss.Computer.Browser.help()

    put_file(c, "/home/apps/notes/ui/index.lui", ~S"""
    <lua>
      local d = db.open("data/notes.dbl")
      d:exec("create table if not exists note (text text)")
      page.title = "Notes"
      function post.add(req) d:exec("insert into note values (?)", req.form.text) end
    </lua>
    <form post="add"><input name="text" label="Note"/><button>Keep</button></form>
    <a href="all">All notes</a>
    """)

    put_file(c, "/home/apps/notes/ui/all.lui", ~S"""
    <lua>local d = db.open("data/notes.dbl") page.title = "All notes"</lua>
    <ul>{% for _, r in ipairs(d:query("select text from note")) do %}<li>{{ r.text }}</li>{% end %}</ul>
    """)

    put_file(c, "/home/manifest.org", "* Apps\n- [[org:#{c}/notes]]\n")
    :ok = Moss.Owners.claim(c, "tester")
    hx = as("tester") |> put_req_header("hx-request", "true")
    assert post(hx, "/computers/#{c}/app/notes/?do=add", %{"text" => "seeds"}).resp_body =~ "Keep"

    assert %{code: 0, out: out} = Computer.run(c, "open app/notes/all")
    assert out =~ "seeds"

    assert %{code: 0, out: out} = Computer.run(c, "open app/notes")
    assert out =~ ~s(field "Note")
    assert %{code: 0} = Computer.run(c, "type Note water")
    assert %{code: 0} = Computer.run(c, "click Keep")
    assert %{code: 0, out: out} = Computer.run(c, "open app/notes/all")
    assert out =~ "water" and out =~ "seeds"
  end
end

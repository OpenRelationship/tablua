defmodule MossWeb.AppTest do
  # Apps the person opens (Arock PROJECT.md §14.7, goal 5): the computer serves its Lua app as HTML and htmx, the
  # person's browser draws it, and the agent reads the same page as words and controls with its own browser.
  use MossWeb.ConnCase, async: false

  alias Moss.Computer
  alias Moss.Computer.Disk

  defp as(person), do: Plug.Test.init_test_session(build_conn(), person: person)
  defp cid, do: "app-#{System.unique_integer([:positive])}"

  defp put_file(c, path, text),
    do: :ok = Disk.write(:sys.get_state(Computer.wake!(c)).disk, path, text)

  @app ~S"""
  local ui = require("shroomi")
  local function page(d)
    local rows = d:query("select name from plant order by name")
    return ui.page{ title = "Plants", ui.raw(ui.template([[
      <h1>Plants</h1>
      <ul>{{#rows}}<li>{{name}} <button hx-delete="plants/{{name}}">Remove {{name}}</button></li>{{/rows}}</ul>
      <form hx-post="plants"><label>Name <input name="name"></label><button>Add</button></form>
      <a hx-get="about">About</a>
      <script>alert(1)</script><img src="x" onerror="alert(2)"><a href="javascript:alert(3)">x</a>]], { rows = rows })) }
  end
  return function(req)
    local d = db.open("plants.db")
    d:exec("create table if not exists plant (name text primary key)")
    if req.method == "POST" and req.path == "/plants" then
      d:exec("insert or ignore into plant values (?)", req.form.name)
      return { redirect = "./" }
    elseif req.method == "DELETE" then
      d:exec("delete from plant where name = ?", string.match(req.path, "^/plants/(.+)$"))
      return { status = 200, body = "" }
    elseif req.path == "/about" then
      return ui.page{ title = "About", ui.p"A plant list, by an agent." }
    elseif req.path == "/boom" then
      error("no such plant")
    elseif req.path == "/script" then
      return { body = "alert(1)", headers = { ["content-type"] = "text/javascript" } }
    end
    return page(d)
  end
  """

  test "the person opens the app: HTML with htmx, the agent's scripts unable to run" do
    c = cid()
    Moss.Owners.claim(c, "tester")
    put_file(c, "/home/app.lua", @app)

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
               "http://www.example.com/shroomi/htmx-2.0.4.min.js http://www.example.com/shroomi/shroomi.js;"

    assert csp =~ "connect-src http://www.example.com/computers/#{c}/app/;"
    refute csp =~ "unsafe-eval"
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]

    # htmx posts without a CSRF token, and the app's redirect stays inside it
    conn = post(as("tester"), "/computers/#{c}/app/plants", %{"name" => "fern"})
    assert redirected_to(conn, 303) == "http://www.example.com/computers/#{c}/app/"
    assert get(as("tester"), "/computers/#{c}/app/").resp_body =~ "<li>fern"

    # an app cannot serve a script, and its failures are its own page
    conn = get(as("tester"), "/computers/#{c}/app/script")
    assert get_resp_header(conn, "content-type") == ["text/plain; charset=utf-8"]
    conn = get(as("tester"), "/computers/#{c}/app/boom")
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
    put_file(c, "/home/app.lua", @app)

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

    put_file(c, "/home/app.lua", "return function() error('broken') end")
    assert %{code: 22, err: err} = Computer.run(c, "open app")
    assert err =~ "500"
  end

  # what `help shroomi` tells an agent about apps is how they work: each line it states, done here as written
  test "help shroomi teaches the app and the browser, and what it says holds" do
    c = cid()
    assert %{code: 0, out: help} = Computer.run(c, "help shroomi")

    for line <- [
          "/home/app.lua",
          ~s(hx-post = "add" reaches path "/add"),
          ~s(headers["hx-request"] == "true"),
          "open app/plants",
          "click <id|words>"
        ],
        do: assert(help =~ line, line)

    assert Computer.run(c, "help click").out == Moss.Computer.App.help()

    put_file(c, "/home/app.lua", ~S"""
    local ui = require("shroomi")
    return function(req)
      local d = db.open("notes.db")
      d:exec("create table if not exists note (text text)")
      if req.method == "POST" and req.path == "/add" then
        d:exec("insert into note values (?)", req.form.text)
        if req.headers["hx-request"] == "true" then return ui.render(ui.li(req.form.text)) end
        return { redirect = "notes/all" }
      elseif req.path == "/notes/all" then
        local items = {}
        for i, r in ipairs(d:query("select text from note")) do items[i] = ui.li(r.text) end
        return ui.page{ title = "All notes", ui.ul(items) }
      end
      return ui.page{ title = "Notes",
        ui.form{ post = "add", ui.input{ name = "text", label = "Note" }, ui.button"Keep" } }
    end
    """)

    :ok = Moss.Owners.claim(c, "tester")
    hx = as("tester") |> put_req_header("hx-request", "true")
    assert post(hx, "/computers/#{c}/app/add", %{"text" => "seeds"}).resp_body == "<li>seeds</li>"

    assert redirected_to(post(as("tester"), "/computers/#{c}/app/add", %{"text" => "soil"}), 303) =~
             "notes/all"

    assert %{code: 0, out: out} = Computer.run(c, "open app/notes/all")
    assert out =~ "seeds" and out =~ "soil"

    assert %{code: 0, out: out} = Computer.run(c, "open app")
    assert out =~ ~s(field "Note")
    assert %{code: 0} = Computer.run(c, "type Note water")
    assert %{code: 0} = Computer.run(c, "click Keep")
    assert %{code: 0, out: out} = Computer.run(c, "open app/notes/all")
    assert out =~ "water"
  end
end

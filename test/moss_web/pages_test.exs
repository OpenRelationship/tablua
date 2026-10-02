defmodule MossWeb.PagesTest do
  # Arock's feature file-kinds, bdd/file-kinds.feature's page scenarios: a .lui page is served at its path in its
  # app, what it prints is escaped, an action is named once and the page comes back to be merged, and a page that
  # does not compile says its file and line.
  use MossWeb.ConnCase, async: false

  alias Moss.Computer

  @plants """
  <lua>
    local d = db.open("data/plants.dbl")
    d:exec("create table if not exists plant (name text primary key, watered text)")
    if not d:one("select 1 as x from plant") then
      d:exec("insert into plant values ('Fern', null), ('<script>alert(1)</script>', null)")
    end
    page.title = "Plants"
    function post.water(req) d:exec("update plant set watered = 'today' where name = ?", req.form.name) end
    function post.only(req) d:exec("update plant set watered = 'today' where name = ?", req.form.name) return "#plants" end
  </lua>
  <card title="Plants">
    <ul id="plants">
      {% for _, p in ipairs(d:query("select * from plant order by name")) do %}
        <li class="flex gap-2">{{ p.name }}: {{ p.watered or "dry" }}
          <button size="sm" post="water" vals={{ {name = p.name} }}>Water</button>
        </li>
      {% end %}
    </ul>
  </card>
  """

  defp as, do: Plug.Test.init_test_session(build_conn(), person: "tester")
  defp hx(conn), do: put_req_header(conn, "hx-request", "true")

  setup do
    id = "pages-#{System.unique_integer([:positive])}"

    files = %{
      "apps/plants/ui/index.lui" => @plants,
      "apps/plants/ui/_row.lui" => "<li>part</li>",
      "ui/index.lui" => ~s(<lua>page.title = "Home"</lua><p class="text-sm">Home</p>),
      "ui/bad.lui" => ~s(<div>\n  <p class="p-4 glow-9000">x</p>\n</div>)
    }

    %{"code" => 0} = Computer.exec(id, %{"cwd" => "/home", "cmd" => "true", "files" => files})
    :ok = Moss.Owners.claim(id, "tester")
    %{id: id, base: "/computers/#{id}/app/"}
  end

  test "Scenario: a page is served at its path, in its app's folder", %{id: id, base: base} do
    conn = get(as(), base <> "plants")
    assert conn.status == 200
    assert conn.resp_body =~ "<title>Plants</title>"
    assert conn.resp_body =~ ~s(<base href="/computers/#{id}/app/plants/">)
    assert conn.resp_body =~ "<h2>Plants</h2>"
    assert conn.resp_body =~ ~s(<script src="/shroomi/idiomorph-0.7.3.min.js">)
    assert get(as(), base).resp_body =~ "<title>Home</title>"
    assert get(as(), base <> "plants/_row").status == 404
    # the app's database is the app's own
    assert %{"stdout" => "plants.dbl\n"} =
             Computer.exec(id, %{"cwd" => "/home", "cmd" => "ls apps/plants/data"})
  end

  test "Scenario: what a page prints is escaped", %{base: base} do
    body = get(as(), base <> "plants").resp_body
    assert body =~ "&lt;script&gt;alert(1)&lt;/script&gt;: dry <button"
    refute body =~ "<script>alert"
  end

  test "an action is named once, and the whole page comes back to be merged", %{base: base} do
    body = get(as(), base <> "plants").resp_body
    assert body =~ ~s(data-morph="" data-size="sm" hx-post="?do=water")

    conn = post(hx(as()), base <> "plants/?do=water", %{"name" => "Fern"})
    assert conn.status == 200
    assert conn.resp_body =~ "<!doctype html>"
    assert conn.resp_body =~ "Fern: today"
  end

  test "Scenario: an action re-renders one element", %{base: base} do
    conn = post(hx(as()), base <> "plants/?do=only", %{"name" => "Fern"})
    assert conn.resp_body =~ ~s(<body data-part="plants")
    assert conn.resp_body =~ "Fern: today"
    refute conn.resp_body =~ ~s(<div class="card">)
  end

  test "Scenario: a page with an unknown class fails, naming its file, line and class", %{
    id: id,
    base: base
  } do
    conn = get(as(), base <> "bad")
    assert conn.status == 500
    assert conn.resp_body =~ ~s(ui/bad.lui:2: no class "glow-9000")
    assert %{"code" => 0} = Computer.exec(id, %{"cwd" => "/home", "cmd" => "true"})
  end
end

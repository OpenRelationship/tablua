defmodule Moss.PersonCheckTest do
  # The build suite's hidden check, held against a page that works and one that does not.
  use ExUnit.Case, async: false

  alias Moss.Computer

  @works """
  <lua>
  local d = db.open("data/plants.dbl")
  d:exec("create table if not exists plant (name text primary key)")
  function post.add(req) d:exec("insert into plant values (?)", req.form.name) end
  </lua>
  <form post="add"><input name="name"/><button>Add</button></form>
  {% for _, p in ipairs(d:query("select * from plant")) do %}<p>{{ p.name }}</p>{% end %}
  """

  defp computer(page) do
    id = "person-#{System.unique_integer([:positive])}"
    Computer.exec(id, %{"cwd" => "/home", "cmd" => "true", "files" => %{"ui/index.lui" => page}})
    id
  end

  test "a page that adds what the person adds works" do
    assert %{status: 200, added: true} = Moss.PersonCheck.uses(computer(@works), "/")
  end

  # a second page's form posts relative to it, as a browser resolves it: pantry?do=add on /pantry is /pantry
  test "a form on a second page is posted where a browser would post it" do
    id = computer(@works)
    Computer.exec(id, %{"cmd" => "true", "files" => %{"ui/pantry.lui" => @works}})
    assert %{status: 200, form: 200, added: true} = Moss.PersonCheck.uses(id, "/pantry")
  end

  test "a page whose table was never made, or that only says it added, does not" do
    broken =
      String.replace(
        @works,
        ~s|d:exec("create table if not exists plant (name text primary key)")\n|,
        ""
      )

    assert %{added: false} = Moss.PersonCheck.uses(computer(broken), "/")

    pretend =
      String.replace(@works, ~s|d:exec("insert into plant values (?)", req.form.name)|, "")

    assert %{status: 200, added: false} = Moss.PersonCheck.uses(computer(pretend), "/")
  end
end

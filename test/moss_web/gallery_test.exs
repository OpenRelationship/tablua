defmodule MossWeb.GalleryTest do
  # Shroomi's gallery (Arock PROJECT.md §16): every example is an app written only in Shroomi, served by a
  # computer to its person, using no class Shroomi does not know, and working through htmx's requests.
  use MossWeb.ConnCase, async: false

  alias Moss.Computer

  @examples Path.join(Application.compile_env!(:moss, :core), "submodules/shroomi/examples")
  @names ~w(plants notes dashboard settings report inbox)

  defp as, do: Plug.Test.init_test_session(build_conn(), person: "tester")

  setup do
    id = "gallery-#{System.unique_integer([:positive])}"

    files =
      for f <- Path.wildcard(@examples <> "/*.lua"),
          into: %{"app.lua" => File.read!(@examples <> "/app.lua")},
          do: {"examples/" <> Path.basename(f), File.read!(f)}

    %{"code" => 0} = Computer.exec(id, %{"cwd" => "/home", "cmd" => "true", "files" => files})
    :ok = Moss.Owners.claim(id, "tester")
    %{id: id, base: "/computers/#{id}/app/"}
  end

  # the classes Shroomi does not know, by Shroomi's own check, run on the computer
  defp unknown(id, html) do
    Computer.exec(id, %{
      "cwd" => "/tmp",
      "cmd" => ~s|lua -e 'print(table.concat(require("shroomi").check(fs.read("p.html")), " "))'|,
      "files" => %{"p.html" => html}
    })["stdout"]
    |> String.trim()
  end

  test "the gallery and every example, and its Lua, are pages with no unknown class", %{
    id: id,
    base: base
  } do
    for path <- [""] ++ Enum.flat_map(@names, &["#{&1}/", "#{&1}/code"]) do
      conn = get(as(), base <> path)
      assert conn.status == 200, "#{path}: #{conn.status} #{String.slice(conn.resp_body, 0, 300)}"
      assert conn.resp_body =~ "Shroomi", path

      assert unknown(id, conn.resp_body) == "",
             "#{path} uses classes Shroomi does not know: #{unknown(id, conn.resp_body)}"
    end
  end

  # Shroomi's check 7 (§16.1): a typical page is rendered on tv-labs lua, cleaned and sent in under 50 ms. The
  # median of seven requests, after one to wake the computer.
  test "every gallery page is served in under 50 ms", %{base: base} do
    times =
      for path <- [""] ++ Enum.map(@names, &"#{&1}/") do
        get(as(), base <> path)

        ms =
          for _ <- 1..7 do
            {us, conn} = :timer.tc(fn -> get(as(), base <> path) end)
            200 = conn.status
            us / 1000
          end
          |> Enum.sort()
          |> Enum.at(3)

        {path, ms}
      end

    IO.puts(
      "\n" <> Enum.map_join(times, "\n", fn {p, ms} -> "  /#{p}  #{Float.round(ms, 1)} ms" end)
    )

    for {p, ms} <- times, do: assert(ms < 50, "/#{p} took #{ms} ms")
  end

  test "the examples work through htmx's requests", %{base: base} do
    hx = fn conn -> put_req_header(conn, "hx-request", "true") end

    # plants: add, then water, each answered with the list alone
    list = post(hx.(as()), base <> "plants/add", %{"name" => "Pothos", "every" => "5"}).resp_body
    assert list =~ ~s(id="plants") and list =~ "Pothos" and not (list =~ "<html")
    assert post(hx.(as()), base <> "plants/water", %{"name" => "Pothos"}).resp_body =~ "in 5 days"

    # notes: a new note, then its preview as it is typed
    assert redirected_to(post(as(), base <> "notes/new", %{"title" => "Seed list"}), 303) =~
             "notes/note/seed-list"

    assert post(hx.(as()), base <> "notes/save/seed-list", %{"text" => "# Seeds\n\n*basil*"}).resp_body =~
             "<em>basil</em>"

    assert get(as(), base <> "notes/note/seed-list").resp_body =~ "# Seeds"

    # settings: the server says what is wrong, then keeps what is right
    bad = post(hx.(as()), base <> "settings/save", %{"name" => "", "email" => "nope"}).resp_body
    assert bad =~ "A name, please." and bad =~ "That is not an address."

    good =
      post(hx.(as()), base <> "settings/save", %{
        "name" => "Rocky",
        "email" => "r@example.com",
        "tone" => "brief"
      })

    assert good.resp_body =~ "Saved"
    assert get(as(), base <> "settings/").resp_body =~ ~s(value="Rocky")

    # inbox: a letter loads alone for htmx, in the page otherwise
    assert get(hx.(as()), base <> "inbox/letter/3").resp_body =~ "Ordered two bags"
    refute get(hx.(as()), base <> "inbox/letter/3").resp_body =~ "<html"
  end
end

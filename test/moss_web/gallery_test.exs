defmodule MossWeb.GalleryTest do
  # Shroomi's gallery (Arock PROJECT.md §16, feature file-kinds): every example is an app of the computer under
  # apps/<name>/, its page a .lui file, served to its person, using no class Shroomi does not know, and working
  # through its actions.
  use MossWeb.ConnCase, async: false

  alias Moss.Computer

  @examples Path.join(Application.compile_env!(:moss, :core), "submodules/shroomi/examples")
  @names ~w(plants notes dashboard settings report inbox)

  defp as, do: Plug.Test.init_test_session(build_conn(), person: "tester")

  setup do
    id = "gallery-#{System.unique_integer([:positive])}"

    # the gallery as `mix moss.put` puts it on its computer, its addresses naming this one
    files =
      for f <- Path.wildcard(@examples <> "/**/*.{lui,org}"),
          into: %{},
          do:
            {Path.relative_to(f, @examples),
             String.replace(File.read!(f), "org:shroomi-gallery", "org:" <> id)}

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

  test "the gallery and every example, and its page, are pages with no unknown class", %{
    id: id,
    base: base
  } do
    for path <- [""] ++ Enum.flat_map(@names, &["#{&1}/", "source?app=#{&1}"]) do
      conn = get(as(), base <> path)
      assert conn.status == 200, "#{path}: #{conn.status} #{String.slice(conn.resp_body, 0, 300)}"
      assert conn.resp_body =~ "Shroomi", path

      assert unknown(id, conn.resp_body) == "",
             "#{path} uses classes Shroomi does not know: #{unknown(id, conn.resp_body)}"
    end
  end

  # Shroomi's check 7 (§16.1): a typical page is rendered on tv-labs lua, cleaned and sent in under 50 ms. The
  # median of seven requests, after one to wake the computer.
  # Arock's feature manifest (goal 4): every org: link in the gallery names something on the node
  test "the gallery's links resolve", %{id: id} do
    links =
      for f <- Path.wildcard(@examples <> "/**/*.{lui,org}"),
          [_, a] <- Regex.scan(~r/\[\[(org:[^\]]+)\]/, File.read!(f)),
          do: String.replace(a, "org:shroomi-gallery", "org:" <> id)

    assert length(links) >= 6
    for a <- links, do: assert({:ok, _} = Moss.Names.resolve(a), a)
    assert {:error, _} = Moss.Names.resolve("org:#{id}/no-such-app")
  end

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

    # plants: add, then water; each answer is the page again, to be merged
    page =
      post(hx.(as()), base <> "plants/?do=add", %{"name" => "Pothos", "every" => "5"}).resp_body

    assert page =~ "<!doctype html>" and page =~ "Pothos"

    assert post(hx.(as()), base <> "plants/?do=water", %{"name" => "Pothos"}).resp_body =~
             "in 5 days"

    # notes: a new note, then its preview alone as it is typed
    assert redirected_to(post(as(), base <> "notes/?do=new", %{"title" => "Seed list"}), 303) =~
             "notes/?note=seed-list"

    preview =
      post(hx.(as()), base <> "notes/?note=seed-list&do=save", %{"text" => "# Seeds\n\n*basil*"}).resp_body

    assert preview =~ ~s(<body data-part="preview") and preview =~ "<em>basil</em>"
    assert get(as(), base <> "notes/?note=seed-list").resp_body =~ "# Seeds"

    # settings: the server says what is wrong, then keeps what is right
    bad =
      post(hx.(as()), base <> "settings/?do=save", %{"name" => "", "email" => "nope"}).resp_body

    assert bad =~ "A name, please." and bad =~ "That is not an address."

    good =
      post(hx.(as()), base <> "settings/?do=save", %{
        "name" => "Rocky",
        "email" => "r@example.com",
        "tone" => "brief"
      })

    assert good.resp_body =~ "Saved"
    assert get(as(), base <> "settings/").resp_body =~ ~s(value="Rocky")

    # inbox: a letter opens with a get action, the page around it the same
    letter = get(hx.(as()), base <> "inbox/?do=open&id=3").resp_body
    assert letter =~ "Ordered two bags" and letter =~ "Cuttings are rooted"
  end
end

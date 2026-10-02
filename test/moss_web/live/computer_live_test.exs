defmodule MossWeb.ComputerLiveTest do
  # The computer's desktop holds the person's app in a window (Arock PROJECT.md §16.1, check 6): a sandboxed
  # frame with an opaque origin, reloaded when the agent changes what it serves.
  use MossWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Moss.Computer

  @page ~S"""
  <lua>page.title = "Hello"</lua>
  <p>one</p>
  """

  setup do
    id = "live-#{System.unique_integer([:positive])}"
    :ok = Moss.Owners.claim(id, "tester")
    %{id: id}
  end

  defp frame_src(view) do
    view
    |> render()
    |> LazyHTML.from_fragment()
    |> LazyHTML.query("#app-frame")
    |> LazyHTML.attribute("src")
  end

  defp eventually(f, tries \\ 100) do
    cond do
      f.() -> true
      tries == 0 -> false
      true -> Process.sleep(20) && eventually(f, tries - 1)
    end
  end

  test "the app is a sandboxed frame: scripts and forms, no same origin, no referrer", %{
    conn: conn,
    id: id
  } do
    {:ok, view, _} = live(conn, "/computers/#{id}")
    assert has_element?(view, "#app-empty")
    refute has_element?(view, "#app-frame")

    %{"code" => 0} = Computer.exec(id, %{"cmd" => "true", "files" => %{"ui/index.lui" => @page}})
    assert eventually(fn -> has_element?(view, "#app-frame") end)

    frame = view |> render() |> LazyHTML.from_fragment() |> LazyHTML.query("#app-frame")
    assert LazyHTML.attribute(frame, "sandbox") == ["allow-scripts allow-forms"]
    assert LazyHTML.attribute(frame, "referrerpolicy") == ["no-referrer"]
    assert [src] = LazyHTML.attribute(frame, "src")
    prefix = "/computers/#{id}/frame/"
    assert String.starts_with?(src, prefix)
    [cap, ""] = src |> String.replace_prefix(prefix, "") |> String.split("/")
    assert {:ok, "tester"} = MossWeb.Frame.check(cap, id)

    # the frame's src opens the app on its own, with no session
    assert get(build_conn(), src).resp_body =~ "one"
  end

  test "the agent's write to its page reloads the frame; the person's own requests do not",
       %{
         conn: conn,
         id: id
       } do
    %{"code" => 0} = Computer.exec(id, %{"cmd" => "true", "files" => %{"ui/index.lui" => @page}})
    {:ok, view, _} = live(conn, "/computers/#{id}")
    [first] = frame_src(view)

    # the person using the app writes its database (actor "user"): no reload
    Phoenix.PubSub.subscribe(Moss.PubSub, "home:" <> id)

    write_db =
      ~S|<lua>local d = db.open("data/x.dbl"); d:exec("create table if not exists t (a)")</lua><p>ok</p>|

    %{"code" => 0} =
      Computer.exec(id, %{
        "cmd" => "true",
        "files" => %{"ui/index.lui" => write_db}
      })

    assert_receive {:home_changed, ^id}
    assert eventually(fn -> frame_src(view) != [first] end)
    [second] = frame_src(view)

    get(build_conn(), second)
    refute_receive {:home_changed, ^id}, 200

    # the agent changes its app: a new src, so the frame loads again
    %{"code" => 0} =
      Computer.exec(id, %{
        "cmd" => "true",
        "files" => %{"ui/index.lui" => String.replace(@page, "one", "two")}
      })

    assert eventually(fn -> frame_src(view) != [second] end)
    [third] = frame_src(view)
    assert get(build_conn(), third).resp_body =~ "two"
  end
end

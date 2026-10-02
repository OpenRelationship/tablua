defmodule MossWeb.FrameTest do
  # The LiveView window (Arock PROJECT.md §16.1, check 6): the person's app is drawn in a sandboxed frame with an
  # opaque origin, so its requests carry no cookie Moss relies on. Each is authorized by the capability in its
  # path alone (`MossWeb.Frame`), for a person who still owns the computer, and answered to the frame's `null`
  # origin with CORS.
  use MossWeb.ConnCase, async: false

  alias Moss.Computer
  alias MossWeb.Frame

  @page ~S"""
  <lua>
    local d = db.open("data/plants.dbl")
    d:exec("create table if not exists plant (name text primary key)")
    page.title = "Plants"
    function post.plant(req)
      d:exec("insert or ignore into plant values (?)", req.form.name)
      return { redirect = "./" }
    end
    function get.more() return "#more" end
  </lua>
  <h1>Plants</h1>
  <ul>{% for _, r in ipairs(d:query("select name from plant order by name")) do %}<li>{{ r.name }}</li>{% end %}</ul>
  <p id="more">swapped</p>
  """

  setup do
    id = "frame-#{System.unique_integer([:positive])}"
    :ok = Moss.Owners.claim(id, "tester")
    %{"code" => 0} = Computer.exec(id, %{"cmd" => "true", "files" => %{"ui/index.lui" => @page}})
    cap = Frame.cap("tester", id)
    %{id: id, cap: cap, base: Frame.base(id, cap)}
  end

  defp anon, do: build_conn()
  defp null_origin(conn), do: put_req_header(conn, "origin", "null")

  test "the cap alone opens the app, with its base, policy and CORS for the opaque origin", %{
    base: base
  } do
    conn = get(null_origin(anon()), base)
    assert html_response(conn, 200) =~ "<h1>Plants</h1>"
    assert conn.resp_body =~ ~s(<base href="#{base}">)

    [csp] = get_resp_header(conn, "content-security-policy")
    assert csp =~ "connect-src http://www.example.com#{base};"
    assert csp =~ "form-action http://www.example.com#{base};"
    assert csp =~ "base-uri http://www.example.com#{base};"
    assert csp =~ "frame-ancestors 'self'"
    assert get_resp_header(conn, "x-content-type-options") == ["nosniff"]
    assert get_resp_header(conn, "referrer-policy") == ["no-referrer"]

    assert get_resp_header(conn, "access-control-allow-origin") == ["*"]
    assert get_resp_header(conn, "access-control-allow-credentials") == []
    assert get_resp_header(conn, "set-cookie") == []

    # the path without its slash comes back to it, cap and all
    assert redirected_to(get(anon(), String.trim_trailing(base, "/")), 302) == base
  end

  test "htmx's requests: a preflight, then the swap, its headers readable by the frame", %{
    base: base
  } do
    conn =
      anon()
      |> null_origin()
      |> put_req_header("access-control-request-method", "POST")
      |> put_req_header("access-control-request-headers", "hx-request,hx-current-url,hx-target")
      |> options(base <> "?do=plant")

    assert conn.status == 204
    assert get_resp_header(conn, "access-control-allow-origin") == ["*"]
    [methods] = get_resp_header(conn, "access-control-allow-methods")
    for m <- ~w(GET POST PUT PATCH DELETE), do: assert(methods =~ m)
    [allowed] = get_resp_header(conn, "access-control-allow-headers")
    for h <- ~w(hx-request hx-current-url hx-target hx-trigger), do: assert(allowed =~ h)
    assert get_resp_header(conn, "access-control-allow-credentials") == []

    conn = anon() |> null_origin() |> put_req_header("hx-request", "true") |> get(base <> "?do=more")
    assert conn.resp_body =~ ~s(data-part="more")
    refute conn.resp_body =~ "<base"
    [exposed] = get_resp_header(conn, "access-control-expose-headers")
    assert exposed =~ "hx-trigger"

    # a form post's redirect stays inside the cap's path
    conn = post(null_origin(anon()), base <> "?do=plant", %{"name" => "fern"})
    assert redirected_to(conn, 303) == "http://www.example.com" <> base
    assert get_resp_header(conn, "access-control-allow-origin") == ["*"]
    assert get(anon(), base).resp_body =~ "<li>fern"
  end

  test "a cap that is bad, expired, for another computer or for someone no longer its owner is refused",
       %{id: id, cap: cap} do
    other = "frame-other-#{System.unique_integer([:positive])}"
    :ok = Moss.Owners.claim(other, "tester")

    expired =
      Phoenix.Token.sign(MossWeb.Endpoint, "app-frame", {"tester", id},
        signed_at: System.system_time(:second) - 7200
      )

    # "other" never owned it, as a cap minted before a computer changed hands would name
    not_owner = Frame.cap("other", id)
    forged = String.slice(cap, 0..-3//1) <> "xx"

    for {why, path} <- [
          bad: Frame.base(id, forged),
          garbage: Frame.base(id, "nonsense"),
          expired: Frame.base(id, expired),
          another_computer: Frame.base(other, cap),
          not_owner: Frame.base(id, not_owner)
        ] do
      assert get(anon(), path).status == 403, "#{why}"
      assert post(anon(), path <> "?do=plant", %{"name" => "x"}).status == 403, "#{why}"
      assert options(anon(), path).status == 403, "#{why}"
    end

    # a person the config no longer lets in is no one's owner
    Application.put_env(:moss, :page_tokens, %{"test-other-token" => "other"})

    try do
      assert get(anon(), Frame.base(id, cap)).status == 403
    after
      Application.put_env(:moss, :page_tokens, %{
        "test-page-token" => "tester",
        "test-other-token" => "other"
      })
    end
  end

  test "a session cookie opens no frame path, and a cap opens nothing but the frame", %{
    id: id,
    cap: cap
  } do
    signed_in = Plug.Test.init_test_session(build_conn(), person: "tester")
    assert get(signed_in, "/computers/#{id}/frame/nonsense/").status == 403

    # the app's own route still wants the session, whatever cap rides along
    conn = get(anon(), "/computers/#{id}/app/#{cap}/")
    assert redirected_to(conn, 302) =~ "/login"
    conn = get(anon(), "/computers/#{id}/app/?cap=#{cap}")
    assert redirected_to(conn, 302) =~ "/login"
    conn = get(anon(), "/computers/#{id}")
    assert redirected_to(conn, 302) =~ "/login"
  end

  test "a cap from another purpose's token is not a frame cap", %{id: id} do
    token = Phoenix.Token.sign(MossWeb.Endpoint, "something-else", {"tester", id})
    assert get(anon(), Frame.base(id, token)).status == 403
  end
end

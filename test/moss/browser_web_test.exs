defmodule Moss.BrowserWebTest do
  # Arock feature browser: a fetch that looks like a browser's (headers, compression, character sets, meta
  # refresh), a cookie jar per computer, and Referer and Origin.
  use ExUnit.Case, async: false

  alias Moss.Computer
  alias MossBrowser.{Cookies, Page}
  alias Moss.Computer.Net

  setup do
    Application.put_env(:moss, :resolver, fn _ -> [{93, 184, 215, 14}] end)
    on_exit(fn -> Application.delete_env(:moss, :resolver) end)
  end

  defp sh(c, line), do: Computer.run(c, line)
  defp host(conn), do: conn |> Plug.Conn.get_req_header("host") |> List.first()
  defp header(conn, name), do: conn |> Plug.Conn.get_req_header(name) |> List.first()

  defp web(f) do
    Req.Test.stub(Net, fn conn ->
      case f.(conn.request_path, conn) do
        %Plug.Conn{} = conn -> conn
        {status, body} -> Plug.Conn.send_resp(conn, status, body)
        body -> Plug.Conn.send_resp(conn, 200, body)
      end
    end)

    c = "browser-web-#{System.unique_integer([:positive])}"
    Req.Test.allow(Net, self(), Computer.wake!(c))
    c
  end

  defp text(c), do: Page.text(Computer.Browser.front(Computer.view(c)).page)

  test "a fetch sends a browser's headers, and says it is Arock" do
    test = self()

    c =
      web(fn _, conn ->
        send(test, {:headers, conn.req_headers})
        "<title>Hi</title>"
      end)

    sh(c, "open https://example.com/")
    assert_received {:headers, h}
    h = Map.new(h)
    assert h["accept"] =~ "text/html"
    assert h["accept-language"] =~ "en"
    assert h["accept-encoding"] =~ "gzip"
    assert h["accept-encoding"] =~ "deflate"
    assert h["user-agent"] =~ ~r{^Arock/1\.0 .*\+https://arock\.ai/agent}
    refute h["user-agent"] =~ "Safari"
  end

  test "a compressed answer is inflated, and inflating stops at the cap" do
    gz = fn conn, body ->
      conn
      |> Plug.Conn.put_resp_header("content-encoding", "gzip")
      |> Plug.Conn.send_resp(200, :zlib.gzip(body))
    end

    c =
      web(fn
        "/bomb", conn ->
          gz.(conn, "<title>Bomb</title><p>" <> String.duplicate("a", 60 * 1024 * 1024))

        _, conn ->
          gz.(conn, "<title>Ferns</title><p>Shade loving ferns</p>")
      end)

    assert %{code: 0, out: out} = sh(c, "open https://example.com/")
    assert out =~ "Shade loving ferns"
    assert %{code: 0, out: out} = sh(c, "open https://example.com/bomb")
    assert out =~ "read to 5 MB"
  end

  test "a page in windows-1252 reads right, by its header or its meta" do
    body = "<title>Cafe</title><p>caf\xE9 \x93quoted\x94</p>"

    c =
      web(fn
        "/meta", _ ->
          ~s(<meta charset="windows-1252">) <> body

        _, conn ->
          conn
          |> Plug.Conn.put_resp_content_type("text/html", "windows-1252")
          |> Plug.Conn.send_resp(200, body)
      end)

    sh(c, "open https://example.com/")
    assert text(c) =~ "café “quoted”"
    sh(c, "open https://example.com/meta")
    assert text(c) =~ "café “quoted”"
  end

  test "a page in a set Moss does not decode says so" do
    c =
      web(fn _, conn ->
        conn
        |> Plug.Conn.put_resp_content_type("text/html", "Shift_JIS")
        |> Plug.Conn.send_resp(200, "<title>JP</title><p>\x93\xFA\x96\x7B ok</p>")
      end)

    assert %{code: 0, out: out} = sh(c, "open https://example.com/")
    assert out =~ "Shift_JIS"
    assert text(c) =~ "ok"
  end

  test "a meta refresh is followed" do
    c =
      web(fn
        "/next", _ -> "<title>Next</title><p>arrived</p>"
        _, _ -> ~s(<meta http-equiv="refresh" content="0; url=/next"><title>Wait</title>)
      end)

    assert %{code: 0, out: out} = sh(c, "open https://example.com/")
    assert out =~ "Next\nhttps://example.com/next"
  end

  test "a cookie set on a redirect is sent next time, and listed without its value" do
    c =
      web(fn
        "/login", conn ->
          conn
          |> Plug.Conn.put_resp_header("set-cookie", "sid=s3cret; Path=/; HttpOnly")
          |> Plug.Conn.put_resp_header("location", "/account")
          |> Plug.Conn.send_resp(302, "")

        "/account", conn ->
          "<title>Account</title><p>cookie: #{header(conn, "cookie")}</p>"
      end)

    assert %{code: 0, out: out} = sh(c, "open https://shop.example/login")
    assert out =~ "cookie: sid=s3cret"
    assert %{code: 0, out: out} = sh(c, "cookies")
    assert out =~ "shop.example"
    assert out =~ "sid"
    refute out =~ "s3cret"
    assert %{code: 0} = sh(c, "cookies clear shop.example")
    assert %{out: out} = sh(c, "open https://shop.example/account")
    refute out =~ "s3cret"
  end

  test "curl keeps no cookies" do
    c =
      web(fn
        "/set", conn ->
          conn
          |> Plug.Conn.put_resp_header("set-cookie", "a=1")
          |> Plug.Conn.send_resp(200, "<title>Set</title>")

        _, conn ->
          "cookie=#{header(conn, "cookie")}"
      end)

    sh(c, "open https://shop.example/set")
    assert %{out: "cookie=" <> rest} = sh(c, "curl https://shop.example/")
    assert rest == ""
  end

  test "a cookie goes only where it may" do
    jar =
      Cookies.put(
        Cookies.new(),
        URI.parse("https://shop.example/cart/"),
        ["c=1; Secure; Path=/cart"],
        0
      )

    at = &Cookies.header(jar, URI.parse(&1), 0)
    assert at.("https://shop.example/cart/1") == "c=1"
    assert at.("http://shop.example/cart/1") == nil
    assert at.("https://shop.example/") == nil
    assert at.("https://other.example/cart") == nil

    for wide <- ["example", "com", ".com", "co.uk", "93.184.215.14"] do
      jar =
        Cookies.put(
          Cookies.new(),
          URI.parse("https://a.shop.example/"),
          ["w=1; Domain=#{wide}"],
          0
        )

      assert Cookies.header(jar, URI.parse("https://a.shop.example/"), 0) == nil
    end

    jar =
      Cookies.put(
        Cookies.new(),
        URI.parse("https://a.shop.example/"),
        ["d=1; Domain=shop.example"],
        0
      )

    assert Cookies.header(jar, URI.parse("https://b.shop.example/"), 0) == "d=1"

    jar =
      Cookies.put(Cookies.new(), URI.parse("https://shop.example/"), ["e=1; Max-Age=60"], 1_000)

    assert Cookies.header(jar, URI.parse("https://shop.example/"), 1_030) == "e=1"
    assert Cookies.header(jar, URI.parse("https://shop.example/"), 1_061) == nil
  end

  test "links send Referer and forms send Origin" do
    test = self()

    c =
      web(fn path, conn ->
        send(test, {host(conn), path, header(conn, "referer"), header(conn, "origin")})

        ~s(<title>#{path}</title><a href="https://shop.example/item">item</a><a href="https://other.example/">away</a>) <>
          ~s(<a href="http://shop.example/plain">plain</a><form method="post" action="/buy"><button>Buy</button></form>)
      end)

    sh(c, "open https://shop.example/list")
    sh(c, "click item")
    assert_received {"shop.example", "/item", "https://shop.example/list", nil}
    sh(c, "click away")
    assert_received {"other.example", "/", "https://shop.example/", nil}
    sh(c, "back")
    sh(c, "click plain")
    assert_received {"shop.example", "/plain", nil, nil}
    sh(c, "back")
    sh(c, "click Buy")
    assert_received {"shop.example", "/buy", _, "https://shop.example"}
  end
end

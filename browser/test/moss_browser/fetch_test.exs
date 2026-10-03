defmodule MossBrowser.FetchTest do
  # The way to the web: public addresses only, checked again on every redirect; a browser's headers and an honest
  # user-agent; compressed answers inflated under the cap; a cookie jar kept through redirects.
  use ExUnit.Case, async: true

  alias MossBrowser.{Cookies, Fetch}

  def public(_host), do: [{93, 184, 215, 14}]

  defp web(f) do
    name = :"web#{System.unique_integer([:positive])}"

    Req.Test.stub(name, fn conn ->
      case f.(conn.request_path, conn) do
        %Plug.Conn{} = conn -> conn
        {status, body} -> Plug.Conn.send_resp(conn, status, body)
        body -> Plug.Conn.send_resp(conn, 200, body)
      end
    end)

    [resolver: &__MODULE__.public/1, req_options: [plug: {Req.Test, name}]]
  end

  test "a browser's request carries a browser's headers and says it is Arock" do
    test = self()

    opts =
      web(fn _, conn ->
        send(test, {:h, Map.new(conn.req_headers)})
        "hi"
      end)

    assert {:ok, %{status: 200, body: "hi"}} =
             Fetch.get("https://example.com/", [browser: true] ++ opts)

    assert_received {:h, h}
    assert h["accept"] =~ "text/html"
    assert h["accept-encoding"] =~ "gzip"
    assert h["user-agent"] =~ ~r{^Arock/1\.0 .*\+https://arock\.ai/agent}
    assert h["host"] == "example.com"

    assert {:ok, _} = Fetch.get("https://example.com/", [agent: "Tester/2"] ++ opts)
    assert_received {:h, %{"user-agent" => "Tester/2"} = plain}
    refute Map.has_key?(plain, "accept-language")
  end

  test "only http and https to public addresses, and a redirect is checked again" do
    assert {:error, "only http and https"} = Fetch.get("file:///etc/passwd")
    assert {:error, msg} = Fetch.get("https://intranet/", resolver: fn _ -> [{10, 0, 0, 5}] end)
    assert msg =~ "not on the public internet"
    assert {:error, _} = Fetch.get("http://127.0.0.1/")
    assert {:error, _} = Fetch.get("http://169.254.169.254/latest/meta-data/")
    assert {:error, _} = Fetch.get("http://[::1]/")

    opts =
      web(fn _, conn ->
        conn
        |> Plug.Conn.put_resp_header("location", "http://127.0.0.1/admin")
        |> Plug.Conn.send_resp(302, "")
      end)

    assert {:error, msg} = Fetch.get("https://example.com/", opts)
    assert msg =~ "not on the public internet"
  end

  test "a compressed answer is inflated, and inflating stops at the cap" do
    big = String.duplicate("a", 200_000)

    opts =
      web(fn _, conn ->
        conn
        |> Plug.Conn.put_resp_header("content-encoding", "gzip")
        |> Plug.Conn.send_resp(200, :zlib.gzip(big))
      end)

    assert {:ok, %{body: ^big, cut: false}} =
             Fetch.get("https://example.com/", [browser: true] ++ opts)

    assert {:ok, %{body: body, cut: true}} =
             Fetch.get("https://example.com/", [browser: true, max: 1000, cut: true] ++ opts)

    assert byte_size(body) <= 1000
    assert {:error, msg} = Fetch.get("https://example.com/", [browser: true, max: 1000] ++ opts)
    assert msg =~ "over 1000 bytes"
  end

  test "a cookie set on a redirect is sent on the next hop" do
    test = self()

    opts =
      web(fn
        "/login", conn ->
          conn
          |> Plug.Conn.put_resp_header("set-cookie", "sid=abc; Path=/")
          |> Plug.Conn.put_resp_header("location", "/home")
          |> Plug.Conn.send_resp(302, "")

        "/home", conn ->
          send(test, {:cookie, Plug.Conn.get_req_header(conn, "cookie")})
          "welcome"
      end)

    assert {:ok, %{body: "welcome", cookies: jar}} =
             Fetch.get("https://example.com/login", [cookies: Cookies.new()] ++ opts)

    assert_received {:cookie, ["sid=abc"]}
    assert [{"example.com", ["sid"]}] = Cookies.list(jar, System.os_time(:second))
  end

  test "a POST redirected with 303 becomes a GET" do
    test = self()

    opts =
      web(fn
        "/form", conn ->
          conn |> Plug.Conn.put_resp_header("location", "/done") |> Plug.Conn.send_resp(303, "")

        "/done", conn ->
          send(test, {:method, conn.method})
          "ok"
      end)

    assert {:ok, %{body: "ok"}} =
             Fetch.get("https://example.com/form", [method: "POST", body: "a=1"] ++ opts)

    assert_received {:method, "GET"}
  end
end

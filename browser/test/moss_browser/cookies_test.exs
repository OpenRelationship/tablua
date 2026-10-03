defmodule MossBrowser.CookiesTest do
  # A cookie goes only where it may: its domain, its path, https when secure, until it expires; never to a public
  # suffix; listed by name, never by value.
  use ExUnit.Case, async: true

  alias MossBrowser.Cookies

  @now 1_790_000_000
  defp u(s), do: URI.parse(s)

  test "a cookie goes to its host, its parents when it names a domain, and its path" do
    jar =
      Cookies.new()
      |> Cookies.put(
        u("https://shop.example.com/"),
        ["a=1", "b=2; Domain=example.com", "c=3; Path=/cart"],
        @now
      )

    cart = Cookies.header(jar, u("https://shop.example.com/cart/x"), @now)
    assert "c=3; " <> rest = cart
    assert Enum.sort(String.split(rest, "; ")) == ["a=1", "b=2"]

    assert Cookies.header(jar, u("https://www.example.com/"), @now) == "b=2"
    assert Cookies.header(jar, u("https://other.org/"), @now) == nil
    refute Cookies.header(jar, u("https://shop.example.com/"), @now) =~ "c=3"
  end

  test "secure cookies need https, and cookies expire" do
    jar =
      Cookies.new()
      |> Cookies.put(u("https://example.com/"), ["s=1; Secure", "m=2; Max-Age=60"], @now)

    assert Cookies.header(jar, u("http://example.com/"), @now) == "m=2"
    assert Cookies.header(jar, u("https://example.com/"), @now + 61) == "s=1"
  end

  test "a site cannot set a cookie for a public suffix or another site" do
    jar =
      Cookies.new()
      |> Cookies.put(u("https://a.github.io/"), ["x=1; Domain=github.io"], @now)
      |> Cookies.put(u("https://example.com/"), ["y=1; Domain=evil.com"], @now)

    assert Cookies.header(jar, u("https://b.github.io/"), @now) == nil
    assert Cookies.header(jar, u("https://evil.com/"), @now) == nil
  end

  test "a list names sites and cookies, never values, and clear forgets a site" do
    jar = Cookies.put(Cookies.new(), u("https://example.com/"), ["sid=secret"], @now)
    assert Cookies.list(jar, @now) == [{"example.com", ["sid"]}]
    refute inspect(Cookies.list(jar, @now)) =~ "secret"
    assert Cookies.clear(jar, "example.com") == %{}
  end
end

defmodule Moss.BrowserTest do
  # Arock feature browser (context/projects/volvox/features/browser): a light tab, a page read in parts by
  # landmark, and the data a page carries in its HTML (the accessibility tree is moonflower's own test).
  use ExUnit.Case, async: false

  alias Moss.Computer
  alias Moonflower.Page
  alias Moss.Computer.{Browser, Net}

  setup do
    Application.put_env(:moss, :resolver, fn _ -> [{93, 184, 215, 14}] end)
    on_exit(fn -> Application.delete_env(:moss, :resolver) end)
  end

  defp sh(c, line), do: Computer.run(c, line)

  defp web(f) do
    Req.Test.stub(Net, fn conn ->
      case f.(conn.request_path, conn) do
        {status, body} -> Plug.Conn.send_resp(conn, status, body)
        body -> Plug.Conn.send_resp(conn, 200, body)
      end
    end)

    c = "browser-#{System.unique_integer([:positive])}"
    Req.Test.allow(Net, self(), Computer.wake!(c))
    c
  end

  defp front(c), do: Browser.front(Computer.view(c))
  defp heap(term), do: :erts_debug.flat_size(term) * :erlang.system_info(:wordsize)

  # a page with a navigation of 200 links, a main article of 12 sections and a footer
  defp article do
    nav = for i <- 1..200, do: ~s(<li><a href="/n#{i}">Topic #{i}</a></li>)

    sections =
      for s <- 1..12 do
        paras =
          for p <- 1..8,
              do: "<p>Section #{s} paragraph #{p} about the octopus#{s} and its #{p} arms.</p>"

        ~s(<h2>Heading #{s}</h2>#{paras}<a href="/s#{s}">More on #{s}</a>)
      end

    """
    <html><head><title>Octopus</title></head><body>
    <nav><ul>#{nav}</ul></nav>
    <main><h1>Octopus</h1>#{sections}<a href="/n1">Topic 1</a><a href="/n1">Topic 1</a></main>
    <footer><a href="/about">About</a><a href="/privacy">Privacy</a></footer>
    </body></html>
    """
  end

  describe "a light tab" do
    test "a tab keeps no parse tree, and the watcher still sees the page" do
      long =
        "<html><title>Long</title><body><script>bad()</script>" <>
          Enum.map_join(1..2000, &"<p>Paragraph #{&1} about moss and ferns.</p>") <>
          "</body></html>"

      c = web(fn _, _ -> long end)
      assert %{code: 0} = sh(c, "open https://example.com/long")
      tab = front(c)
      refute Map.has_key?(tab.page, :tree)
      assert heap(tab) < byte_size(long)
      assert Page.text(tab.page) =~ "Paragraph 2000 about moss"
      watched = Page.html(tab.page)
      assert watched =~ "Paragraph 1 about moss"
      refute watched =~ "<script"
    end

    test "history keeps twenty addresses, and back fetches again" do
      test = self()

      c =
        web(fn "/" <> n = path, _ ->
          send(test, {:got, path})
          ~s(<title>#{path}</title><a href="/#{String.to_integer(n) + 1}">next</a>)
        end)

      sh(c, "open https://example.com/0")
      for _ <- 1..24, do: sh(c, "click next")
      tab = front(c)
      assert tab.url == "https://example.com/24"
      assert length(tab.history) == 20
      assert Enum.all?(tab.history, &(&1.page == nil))
      flush()
      assert %{code: 0, out: "/23" <> _} = sh(c, "back")
      assert_received {:got, "/23"}
    end

    test "eight tabs at most, the oldest closed with a word" do
      c = web(fn path, _ -> "<title>#{path}</title>" end)
      for i <- 1..8, do: sh(c, "open https://example.com/#{i}")
      assert %{code: 0, out: out} = sh(c, "open https://example.com/9")
      assert out =~ "closed the oldest tab"
      assert %{out: tabs} = sh(c, "tabs")
      refute tabs =~ "example.com/1\n"
      assert tabs =~ "example.com/9"
      assert %{code: 0, out: "closed" <> _} = sh(c, "close")
    end

    test "the computer's file keeps the address and typed values, and the page comes back" do
      test = self()

      c =
        web(fn path, _ ->
          send(test, {:got, path})

          ~s(<title>Search</title><form><input name="q" aria-label="Find"><button>Go</button></form>)
        end)

      sh(c, "open https://example.com/long")
      assert %{code: 0} = sh(c, "type Find fern")
      :ok = Computer.sleep(c)
      flush()
      Req.Test.allow(Net, self(), Computer.wake!(c))
      tab = front(c)
      assert tab.page == nil
      assert tab.url == "https://example.com/long"
      assert byte_size(:erlang.term_to_binary(Browser.kept(Computer.view(c).browser))) < 1_000
      assert %{code: 0, out: out} = sh(c, "ui")
      assert_received {:got, "/long"}
      assert out =~ ~s("Find" = fern)
    end

    test "a page a form answered is shown again without sending the form" do
      test = self()

      c =
        web(fn path, conn ->
          send(test, {:got, conn.method, path})

          case path do
            "/join" ->
              ~s(<title>Joined</title><p>Welcome, Ada</p><a href="/other">other</a>)

            "/other" ->
              "<title>Other</title>"

            _ ->
              ~s(<title>Form</title><form method="post" action="/join"><input name="n"><button>Join</button></form>)
          end
        end)

      sh(c, "open https://example.com/")
      sh(c, "click Join")
      sh(c, "click other")
      flush()
      assert %{code: 0, out: out} = sh(c, "back")
      assert out =~ "Welcome, Ada"
      refute_received {:got, "POST", _}
    end

    test "a page past the cap is read to there" do
      big = "<title>Big</title>" <> String.duplicate("<p>moss moss moss moss</p>", 300_000)
      c = web(fn _, _ -> big end)
      assert %{code: 0, out: out} = sh(c, "open https://example.com/big")
      assert byte_size(big) > 5 * 1024 * 1024
      assert out =~ "read to 5 MB"
    end
  end

  describe "reading in parts" do
    test "a page opens as a map" do
      c = web(fn _, _ -> article() end)
      assert %{code: 0, out: out} = sh(c, "open https://example.com/octopus")
      assert out =~ "Octopus\nhttps://example.com/octopus"
      for s <- 1..12, do: assert(out =~ ~r/\b\d+ +Heading #{s}\n/)
      assert out =~ "navigation: 200 links"
      assert out =~ "footer: 2 links"
      assert out =~ "Section 1 paragraph 1"
      refute out =~ "Topic 150"
      assert byte_size(out) < 8_000
    end

    test "page, read and find" do
      c = web(fn _, _ -> article() end)
      sh(c, "open https://example.com/octopus")
      assert %{code: 0, out: out} = sh(c, "page 2")
      assert out =~ ~r/part 2 of \d+/
      assert %{code: 0, out: out} = sh(c, "read 3")
      assert out =~ "Heading 2"
      assert out =~ "Section 2 paragraph 8"
      refute out =~ "Section 3 paragraph"
      assert %{code: 0, out: out} = sh(c, "page find octopus7")
      assert out =~ "Heading 7"
      assert out =~ "Section 7 paragraph 1"
      refute out =~ "Section 8"
    end

    test "controls come main content first, fifty at a time, repeats once" do
      c = web(fn _, _ -> article() end)
      sh(c, "open https://example.com/octopus")
      assert %{code: 0, out: out} = sh(c, "ui")
      [first | _] = String.split(out, "\n")
      assert first =~ "More on 1"
      assert length(Regex.scan(~r/^\[\d+\]/m, out)) == 50
      assert out =~ "ui more"
      assert length(Regex.scan(~r/"Topic 1"/, out)) <= 1
      assert %{out: more} = sh(c, "ui more")
      assert more =~ "Topic"
      assert %{out: nav} = sh(c, "ui nav")
      assert nav =~ ~s(link "Topic 1")
      refute nav =~ "More on"
    end
  end

  describe "data in the HTML" do
    test "JSON-LD is read without scripts" do
      ld =
        ~s({"@context":"https://schema.org","@type":"Product","name":"Fern","offers":{"@type":"Offer","price":"12.00","priceCurrency":"USD"}})

      c =
        web(fn _, _ ->
          ~s(<html><head><title>Shop</title><meta name="description" content="Plants for shade">) <>
            ~s(<script type="application/ld+json">#{ld}</script></head><body><p>hi</p></body></html>)
        end)

      assert %{code: 0, out: out} = sh(c, "open https://example.com/fern")
      assert out =~ ~s(Product "Fern")
      assert out =~ "12.00 USD"
      assert out =~ "Plants for shade"
    end

    test "the page's data is listed and read" do
      next =
        ~s({"props":{"pageProps":{"title":"Shade plants","items":[{"name":"Fern"},{"name":"Moss"}]}}})

      c =
        web(fn _, _ ->
          ~s(<title>Shop</title><div id="__next"></div><script id="__NEXT_DATA__" type="application/json">#{next}</script>) <>
            ~s(<script>window.__APOLLO_STATE__ = {"a":{"b":"fern frond"}};</script>)
        end)

      sh(c, "open https://example.com/")
      assert %{code: 0, out: out} = sh(c, "data")
      assert out =~ ~r/1 +__NEXT_DATA__ +\d+ bytes/
      assert out =~ "__APOLLO_STATE__"
      assert %{code: 0, out: "Shade plants\n"} = sh(c, "data 1 props.pageProps.title")
      assert %{code: 0, out: out} = sh(c, "data 1 find fern")
      assert out =~ "props.pageProps.items.0.name = Fern"
      assert %{code: 0, out: out} = sh(c, "data 2 a.b")
      assert out =~ "fern frond"
    end
  end

  defp flush do
    receive do
      _ -> flush()
    after
      0 -> :ok
    end
  end
end

defmodule Moss.HTMLPropertyTest do
  # Moss.HTML and the cleaner on input nobody wrote: random bytes and random tag soup built from the shapes
  # mutation XSS is made of (svg and math, their integration points, raw-text elements, comments and CDATA in
  # odd places, every quoting form). Each run draws new input from ExUnit's seed, so a failure names its seed.
  # For every input: the parser never raises, cleaning twice changes nothing, what the cleaner writes, read again
  # by Moss.HTML and by lexbor (the test's own parser, not Moss's), holds only what Shroomi's policy names, and
  # the browser's page for a watcher holds no script.
  use ExUnit.Case, async: true

  alias Moss.Computer.{Clean, Page}

  @runs 1500

  @tags ~w(a b p div span li ul table tr td th tbody caption colgroup col form input button select option textarea
           title style script noscript template iframe xmp noembed noframes plaintext svg math mtext mi mglyph
           malignmark annotation-xml foreignobject desc path g img br hr pre listing frameset body head html meta
           link base object embed h1 h6 dialog details summary label font image)
  @attrs ~w(onclick onerror onload href src action style class id data-x aria-label hx-get hx-on:click hx-vals
            encoding xmlns xlink:href formaction srcdoc color title width viewbox)
  @values [
    "javascript:alert(1)",
    " jav&#x09;ascript:x",
    "text/html",
    "x\" onclick=\"y",
    "</style><img src=x>",
    "<!--",
    "-->",
    "https://ok.example/",
    "expression(alert(1))",
    "js:{a:1}",
    "&quot;&lt;",
    "1"
  ]
  @addresses ~w(href src action formaction xlink:href hx-get hx-post hx-put hx-patch hx-delete hx-push-url)
  @bits [
    "<!--",
    "-->",
    "--!>",
    "<![CDATA[",
    "]]>",
    "</",
    "<",
    ">",
    "/>",
    "&lt;",
    "&amp",
    "&#0;",
    "&#x110000;",
    "\"",
    "'",
    "=",
    " ",
    "\n",
    "\r",
    <<0>>,
    "<?x?>",
    "<!doctype html>",
    "&",
    "`",
    "text",
    "é",
    <<0xFF>>
  ]

  setup_all do
    :rand.seed(:exsss, {ExUnit.configuration()[:seed], 7, 11})
    :ok
  end

  defp pick(list), do: Enum.at(list, :rand.uniform(length(list)) - 1)

  defp soup(0), do: []

  defp soup(n) do
    piece =
      case :rand.uniform(6) do
        1 -> ["<", pick(@tags), attrs(), if(:rand.uniform(4) == 1, do: "/>", else: ">")]
        2 -> ["</", pick(@tags), ">"]
        3 -> pick(@bits)
        4 -> ["<", pick(@tags), " ", pick(@attrs), "=", pick(@values)]
        _ -> pick(@bits) <> pick(@bits)
      end

    [piece | soup(n - 1)]
  end

  defp attrs do
    for _ <- 1..:rand.uniform(3), :rand.uniform(2) == 1 do
      v = pick(@values)

      case :rand.uniform(4) do
        1 -> [" ", pick(@attrs), "=\"", v, "\""]
        2 -> [" ", pick(@attrs), "='", v, "'"]
        3 -> [" ", pick(@attrs), "=", String.replace(v, " ", "")]
        4 -> [" ", pick(@attrs)]
      end
    end
  end

  defp input do
    case :rand.uniform(5) do
      1 -> :crypto.strong_rand_bytes(:rand.uniform(200))
      _ -> IO.iodata_to_binary(soup(:rand.uniform(40)))
    end
  end

  test "random input: never raises, cleans to a fixed point, and holds only what the policy names" do
    p = Clean.policy()
    shell = ~w(html head body title style meta link script)

    for _ <- 1..@runs do
      raw = input()

      for page <- [raw, "<!doctype html><html><head>" <> raw <> "</head><body>" <> raw] do
        assert [{"html", _, [{"head", _, _}, {"body", _, _}]}] = Moss.HTML.parse(page)

        # the browser's page for a watcher: written by Moss.HTML, read by lexbor, no script and no handler in it
        watched = "http://example.com/" |> Page.new(page) |> Page.html()

        for {tag, k, _v, _} <-
              walk(watched |> LazyHTML.from_document() |> LazyHTML.to_tree(), false) do
          refute tag == "script", "a script in the watcher's page from #{inspect(page)}"

          refute k && String.starts_with?(k, "on"),
                 "<#{tag} #{k}> in the watcher's page from #{inspect(page)}"
        end

        out = Clean.html(page)
        again = Clean.html(out)

        assert again == out,
               "not a fixed point:\n#{inspect(page)}\n#{inspect(out)}\n#{inspect(again)}"

        for tree <- [Moss.HTML.parse(out), out |> LazyHTML.from_document() |> LazyHTML.to_tree()],
            {tag, k, v, in_head?} <- walk(tree, false) do
          assert MapSet.member?(p.tags, tag) or tag in shell,
                 "<#{tag}> from #{inspect(page)}\n#{out}"

          assert tag not in ~w(script style title meta link) or in_head?,
                 "<#{tag}> in the body: #{out}"

          if k do
            assert allowed?(p, tag, k), "<#{tag} #{k}> from #{inspect(page)}\n#{out}"
            refute String.starts_with?(k, "on"), "<#{tag} #{k}>"

            if k in @addresses do
              refute v |> String.replace(~r/[\x00-\x20]/, "") |> String.downcase() =~
                       ~r/^(javascript|vbscript):/,
                     "<#{tag} #{k}=#{v}>"
            end
          end
        end
      end
    end
  end

  # every element, and every attribute with its element: {tag, name | nil, value | nil, in the head?}
  defp walk(nodes, in_head?) do
    Enum.flat_map(nodes, fn
      {tag, attrs, kids} ->
        tag = String.downcase(tag)

        [{tag, nil, nil, in_head?}] ++
          for({k, v} <- attrs, do: {tag, String.downcase(k), v, in_head?}) ++
          walk(kids, in_head? or tag == "head")

      _ ->
        []
    end)
  end

  defp allowed?(p, tag, k) do
    tag in ~w(meta link script) or
      MapSet.member?(Map.get(p.attributes, tag, MapSet.new()), k) or
      MapSet.member?(p.attributes["*"], k) or MapSet.member?(p.hx, k) or
      Regex.match?(~r/\A(data|aria)-[a-z0-9_.-]+\z/, k)
  end
end

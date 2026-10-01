defmodule Moss.CleanCorpusTest do
  # Shroomi's check 4 (Arock PROJECT.md §16.1): a published XSS corpus through the cleaner. The vectors are
  # DOMPurify's test fixtures (cure53/DOMPurify test/fixtures/expect.mjs at 368ee78d5280, Apache-2.0, licence in
  # test/fixtures/dompurify), every payload kept and DOMPurify's expected output left out: what matters here is
  # not that the cleaner agrees with DOMPurify but that nothing it lets through can run. The rules below are
  # written from what browsers execute, not read from Shroomi's policy, so the policy is tested, not restated.
  use ExUnit.Case, async: true

  alias Moss.Computer.Clean

  @vectors "test/fixtures/dompurify/vectors.json" |> File.read!() |> Jason.decode!()

  # elements that run script, load a document, or change how the page's addresses or script resolve
  @never ~w(script style iframe frame frameset object embed applet base link meta template noscript portal
            foreignobject math animate animatemotion animatetransform set use image feimage handler listener
            xml import svg:script)

  # attributes whose value is an address
  @addresses ~w(href src action formaction srcset poster data xlink:href background lowsrc dynsrc ping cite
                hx-get hx-post hx-put hx-patch hx-delete hx-push-url)

  test "the corpus is the whole published set, every vector with a payload" do
    assert length(@vectors) == 223
    assert Enum.all?(@vectors, &is_binary(&1["payload"]))
  end

  test "nothing in any vector survives that could run" do
    faults =
      for %{"payload" => payload} = v <- @vectors,
          title = v["title"] || payload,
          fault <- faults(Clean.html(payload)),
          do: "#{title}: #{fault}"

    assert faults == [], Enum.join(faults, "\n")
  end

  test "every vector also stays harmless inside a whole page" do
    for %{"payload" => payload} = v <- @vectors do
      title = v["title"] || payload

      page =
        Clean.html(
          "<!doctype html><html><head><title>t</title></head><body>#{payload}</body></html>"
        )

      assert faults(page) == [], "#{title}: #{inspect(faults(page))}"
      # the shell's only scripts are the pinned assets
      for src <-
            page
            |> LazyHTML.from_document()
            |> LazyHTML.query("script")
            |> LazyHTML.attribute("src") do
        assert src =~ ~r{/shroomi/[a-z0-9.\-]+\.js$}, "#{title}: script #{src}"
      end
    end
  end

  # a payload shaped like a whole document comes back as one: its head is Shroomi's shell (checked above, and its
  # CSS by Moss.CleanTest), so what can run is in its body
  defp faults("<!doctype" <> _ = page) do
    page
    |> LazyHTML.from_document()
    |> LazyHTML.query("body")
    |> LazyHTML.to_tree()
    |> Enum.flat_map(&node_faults/1)
  end

  defp faults(html) do
    html |> LazyHTML.from_fragment() |> LazyHTML.to_tree() |> Enum.flat_map(&node_faults/1)
  end

  defp node_faults({tag, attrs, children}) do
    tag = String.downcase(tag)
    own = if tag in @never, do: ["<#{tag}>"], else: []
    own ++ Enum.flat_map(attrs, &attr_faults(tag, &1)) ++ Enum.flat_map(children, &node_faults/1)
  end

  defp node_faults(_text_or_comment), do: []

  defp attr_faults(tag, {name, value}) do
    name = String.downcase(name)
    v = value |> String.replace(~r/[\x00-\x20]/, "") |> String.downcase()

    cond do
      String.starts_with?(name, "on") ->
        ["<#{tag} #{name}>"]

      name in ~w(srcdoc hx-vars) or String.starts_with?(name, "hx-on") ->
        ["<#{tag} #{name}>"]

      name == "hx-vals" and String.starts_with?(v, ["js:", "javascript:"]) ->
        ["<#{tag} hx-vals=js>"]

      name == "style" and
          String.contains?(v, ["expression(", "javascript:", "-moz-binding", "behavior:"]) ->
        ["<#{tag} style=#{value}>"]

      (name in @addresses or tag == "a") and bad_address?(v) ->
        ["<#{tag} #{name}=#{value}>"]

      true ->
        []
    end
  end

  # A browser's URL parser drops ASCII controls and spaces (stripped above), so a scheme is what the value starts
  # with then. Other Unicode space in front (U+2028, U+00A0, ...) makes a relative path, not a scheme.
  defp bad_address?(v) do
    String.starts_with?(v, [
      "javascript:",
      "vbscript:",
      "livescript:",
      "data:text/html",
      "data:image/svg",
      "data:application",
      "data:text/xml"
    ])
  end
end

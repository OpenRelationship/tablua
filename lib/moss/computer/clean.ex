defmodule Moss.Computer.Clean do
  @moduledoc """
  A page held to Shroomi's policy (`submodules/shroomi/policy.lua`, Arock
  PROJECT.md §16) as it leaves the computer, outside the agent's own run, so a
  page written without Shroomi is held to it too.

  The policy is read once, as data, by a Lua state of its own. Then every page:

    * keeps its document shell only as Shroomi writes it: a title, the charset,
      viewport and htmx-config metas, the pinned stylesheet, the pinned scripts
      (by address, empty) and a `<style>` in the head;
    * keeps the elements the policy names; drops script, style, iframe, object,
      embed, template and the like with all they hold, and unwraps any other
      element to its children;
    * keeps the attributes the policy names, `data-*`, `aria-*` and its htmx
      ones; an address only if relative or of an allowed scheme; drops `on*`,
      `hx-on`, `hx-vars` and an `hx-vals` that would be evaluated.
  """

  @drop ~w(script style iframe object embed template noscript frame frameset applet base link meta title head
           foreignobject math portal)
  @metas %{"viewport" => true, "htmx-config" => true}

  def policy do
    case :persistent_term.get({__MODULE__, :policy}, nil) do
      nil ->
        p = read_policy()
        :persistent_term.put({__MODULE__, :policy}, p)
        p

      p ->
        p
    end
  end

  defp read_policy do
    src = File.read!(Path.join(Moss.Lua.Sources.core(), "submodules/shroomi/policy.lua"))
    {[t], _lua} = Lua.eval!(Lua.new(), src)
    p = deep(t)

    # names compared as the parser gives them, lower case (an SVG's viewBox is viewbox until the browser reads it)
    keys = fn m -> m |> Map.keys() |> Enum.map(&String.downcase/1) |> MapSet.new() end
    assets = p["assets"]

    %{
      tags: keys.(p["tags"]),
      attributes: Map.new(p["attributes"], fn {tag, set} -> {tag, keys.(set)} end),
      hx: keys.(p["hx"]),
      url_attributes: keys.(p["urls"]["attributes"]),
      schemes: keys.(p["urls"]["schemes"]),
      css: assets["css"],
      scripts:
        MapSet.new([assets["htmx"], assets["basecoat"], assets["idiomorph"], assets["shroomi"]]),
      files: assets["files"]
    }
  end

  defp deep(pairs) when is_list(pairs),
    do: Map.new(pairs, fn {k, v} -> {to_string(k), deep(v)} end)

  defp deep(v), do: v

  @doc """
  The page, cleaned: a whole document if it was one, else its body's content. It is cleaned, read back and
  cleaned again, so what leaves is what a parser reads from it: an element the policy unwraps can leave its
  children nested where the parser would not put them (a heading in a heading), and the second reading settles
  them.
  """
  def html(page) when is_binary(page), do: page |> once() |> once()

  defp once(page) do
    p = policy()
    doc? = Regex.match?(~r/^\s*(<!doctype|<html)/i, page)
    [{"html", hattrs, [{"head", _, head}, {"body", battrs, bkids}]}] = Moss.HTML.parse(page)
    body = {"body", attrs("body", battrs, p), nodes(bkids, p)}

    if doc? do
      head = {"head", [], Enum.flat_map(head, &shell(&1, p))}
      "<!doctype html>\n" <> Moss.HTML.to_html([{"html", attrs("html", hattrs, p), [head, body]}])
    else
      {"body", _, inner} = body
      Moss.HTML.to_html(inner)
    end
  end

  # the head, as Shroomi writes it
  defp shell({"title", _, kids}, _p), do: [{"title", [], Enum.filter(kids, &is_binary/1)}]

  # a style's text is written as it is, so it may hold no `<` (nothing that could end it early, or be read as a
  # tag by a browser that does not take it for raw text)
  defp shell({"style", _, kids}, _p) do
    css = kids |> Enum.filter(&is_binary/1) |> Enum.join()
    if css_ok?(css) and not String.contains?(css, "<"), do: [{"style", [], [css]}], else: []
  end

  defp shell({"meta", a, _}, _p) do
    cond do
      attr(a, "charset") ->
        [{"meta", [{"charset", "utf-8"}], []}]

      @metas[attr(a, "name")] ->
        [{"meta", [{"name", attr(a, "name")}, {"content", attr(a, "content") || ""}], []}]

      true ->
        []
    end
  end

  defp shell({"link", a, _}, p) do
    if attr(a, "rel") == "stylesheet" and attr(a, "href") == p.css,
      do: [{"link", [{"rel", "stylesheet"}, {"href", p.css}], []}],
      else: []
  end

  defp shell({"script", a, _}, p) do
    src = attr(a, "src")

    if src in p.scripts,
      do: [{"script", [{"src", src}] ++ if(attr(a, "defer"), do: [{"defer", ""}], else: []), []}],
      else: []
  end

  defp shell(_, _p), do: []

  defp nodes(kids, p), do: Enum.flat_map(kids, &node(&1, p))

  defp node(text, _p) when is_binary(text), do: [text]

  defp node({tag, a, kids}, p) when is_binary(tag) do
    t = String.downcase(tag)

    cond do
      t in @drop -> []
      MapSet.member?(p.tags, t) -> [{t, attrs(t, a, p), nodes(kids, p)}]
      true -> nodes(kids, p)
    end
  end

  defp node(_comment, _p), do: []

  defp attrs(tag, a, p) do
    own = Map.get(p.attributes, tag, MapSet.new())
    all = Map.get(p.attributes, "*", MapSet.new())

    for {k, v} <- a, k = String.downcase(k), keep?(tag, k, v, own, all, p), do: {k, v}
  end

  defp keep?(_tag, k, v, own, all, p) do
    allowed =
      MapSet.member?(own, k) or MapSet.member?(all, k) or MapSet.member?(p.hx, k) or
        Regex.match?(~r/\A(data|aria)-[a-z0-9_.-]+\z/, k)

    allowed and not String.starts_with?(k, "on") and url_ok?(k, v, p) and vals_ok?(k, v) and
      (k != "style" or css_ok?(v))
  end

  # CSS that old browsers ran as script: a script address, IE's expression() and behaviours, Mozilla's and
  # Opera's bindings and links. Read after CSS escapes are decoded and comments and spaces are taken out, so
  # neither `\6a avascript:` nor `java/**/script:` gets by.
  @css_script ["javascript:", "vbscript:", "expression(", "behavior:", "-moz-binding", "-o-link"]
  defp css_ok?(css) do
    plain =
      css
      |> String.replace(~r/\\([0-9a-fA-F]{1,6})\s?/, fn m ->
        [_, hex] = Regex.run(~r/\\([0-9a-fA-F]{1,6})/, m)
        code = String.to_integer(hex, 16)
        if code <= 0x10FFFF and code not in 0xD800..0xDFFF, do: <<code::utf8>>, else: ""
      end)
      |> String.replace(~r/\\(.)/s, "\\1")
      |> String.replace(~r{/\*.*?\*/}s, "")
      |> String.replace(~r/[\s\x00-\x20]/u, "")
      |> String.downcase()

    not String.contains?(plain, @css_script)
  end

  defp url_ok?(k, v, p) do
    if MapSet.member?(p.url_attributes, k) do
      case Regex.run(~r/^\s*([a-zA-Z][a-zA-Z0-9+.-]*):/, String.replace(v, ~r/[\x00-\x20]/, "")) do
        nil -> true
        [_, scheme] -> MapSet.member?(p.schemes, String.downcase(scheme))
      end
    else
      true
    end
  end

  # hx-vals is JSON; a "js:" or "javascript:" prefix would have htmx evaluate it
  defp vals_ok?("hx-vals", v), do: not Regex.match?(~r/^\s*(js|javascript)\s*:/i, v)
  defp vals_ok?(_, _), do: true

  defp attr(a, name), do: Enum.find_value(a, fn {k, v} -> String.downcase(k) == name && v end)
end

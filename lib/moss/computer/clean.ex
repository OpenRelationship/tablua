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
    keys = fn m -> m |> Map.keys() |> MapSet.new() end
    assets = p["assets"]

    %{
      tags: keys.(p["tags"]),
      attributes: Map.new(p["attributes"], fn {tag, set} -> {tag, keys.(set)} end),
      hx: keys.(p["hx"]),
      url_attributes: keys.(p["urls"]["attributes"]),
      schemes: keys.(p["urls"]["schemes"]),
      css: assets["css"],
      scripts: MapSet.new([assets["htmx"], assets["basecoat"], assets["shroomi"]]),
      files: assets["files"]
    }
  end

  defp deep(pairs) when is_list(pairs),
    do: Map.new(pairs, fn {k, v} -> {to_string(k), deep(v)} end)

  defp deep(v), do: v

  @doc "The page, cleaned: a whole document if it was one, else its body's content."
  def html(page) when is_binary(page) do
    p = policy()
    doc? = Regex.match?(~r/^\s*(<!doctype|<html)/i, page)
    tree = page |> LazyHTML.from_document() |> LazyHTML.to_tree()
    html = Enum.find(tree, &match?({"html", _, _}, &1)) || {"html", [], tree}
    {"html", hattrs, kids} = html
    head = for {"head", _, k} <- kids, n <- k, do: n
    body = Enum.find(kids, &match?({"body", _, _}, &1)) || {"body", [], []}
    {"body", battrs, bkids} = body
    body = {"body", attrs("body", battrs, p), nodes(bkids, p)}

    if doc? do
      head = {"head", [], Enum.flat_map(head, &shell(&1, p))}

      "<!doctype html>\n" <>
        LazyHTML.to_html(LazyHTML.from_tree([{"html", attrs("html", hattrs, p), [head, body]}]))
    else
      {"body", _, inner} = body
      LazyHTML.to_html(LazyHTML.from_tree(inner))
    end
  end

  # the head, as Shroomi writes it
  defp shell({"title", _, kids}, _p), do: [{"title", [], Enum.filter(kids, &is_binary/1)}]
  defp shell({"style", _, kids}, _p), do: [{"style", [], Enum.filter(kids, &is_binary/1)}]

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
        String.starts_with?(k, "data-") or String.starts_with?(k, "aria-")

    allowed and not String.starts_with?(k, "on") and url_ok?(k, v, p) and vals_ok?(k, v)
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

defmodule Moss.Computer.Page.Data do
  @moduledoc """
  What a page carries for machines, read without running a script: its meta description and OpenGraph, its
  JSON-LD (schema.org) summed up as `Product "Fern" · price 12.00 USD`, and every JSON it holds (JSON-LD,
  `application/json` scripts such as `__NEXT_DATA__`, and the state a framework assigns, `window.__APOLLO_STATE__
  = {...}` or `var ytInitialData = {...}`), each kept gzipped to be listed and read by path:

      data                     the page's JSON, numbered, with sizes
      data 2 props.pageProps   a value (an index for a list: items.0.name)
      data 2 find fern         the paths whose keys or values hold the words
  """
  import Moss.Computer.Page.Attrs, only: [attr: 2]

  @assign ~r/(?:window\.|self\.|var\s+|let\s+|const\s+)?(__[A-Za-z0-9_]+__|ytInitialData|ytInitialPlayerResponse)\s*=\s*(?=[\[{])/
  @max_blobs 8 * 1024 * 1024

  def read(tree) do
    nodes = all(tree)

    meta =
      for {"meta", a, _} <- nodes,
          k = attr(a, "name") || attr(a, "property"),
          k in ~w(description og:title og:description og:type og:site_name),
          v = attr(a, "content"),
          v not in [nil, ""],
          into: %{},
          do: {k, v}

    scripts =
      for {"script", a, kids} <- nodes, do: {a, kids |> Enum.filter(&is_binary/1) |> Enum.join()}

    blobs =
      scripts
      |> Enum.flat_map(&blob/1)
      |> Enum.reduce({[], 0}, fn {name, raw}, {acc, total} ->
        if total + byte_size(raw) > @max_blobs,
          do: {acc, total},
          else:
            {[%{name: name, size: byte_size(raw), gz: :zlib.gzip(raw)} | acc],
             total + byte_size(raw)}
      end)
      |> elem(0)
      |> Enum.reverse()

    ld =
      for {a, raw} <- scripts,
          attr(a, "type") == "application/ld+json",
          s <- summaries(raw),
          do: s

    %{meta: meta, ld: Enum.take(ld, 5), blobs: blobs}
  end

  defp all(tree),
    do:
      Enum.flat_map(tree, fn
        {_, _, k} = n -> [n | all(k)]
        _ -> []
      end)

  defp blob({a, raw}) do
    type = attr(a, "type") || ""

    cond do
      String.trim(raw) == "" -> []
      type == "application/ld+json" -> [{"JSON-LD", raw}]
      type == "application/json" -> [{attr(a, "id") || "application/json", raw}]
      type in ["", "text/javascript", "module"] -> assigned(raw)
      true -> []
    end
  end

  # the objects a script assigns to a framework's well-known names
  defp assigned(js) do
    for [{at, len}, {n, nl}] <- Regex.scan(@assign, js, return: :index),
        json = balanced(binary_part(js, at + len, byte_size(js) - at - len)),
        do: {binary_part(js, n, nl), json}
  end

  # the JSON value at the start of s, up to its matching bracket (strings minded)
  defp balanced(s), do: balanced(s, 0, 0, false, false)

  defp balanced(s, i, _depth, _str, _esc) when i >= byte_size(s), do: nil

  defp balanced(s, i, depth, str, esc) do
    c = :binary.at(s, i)

    cond do
      str and esc -> balanced(s, i + 1, depth, true, false)
      str and c == ?\\ -> balanced(s, i + 1, depth, true, true)
      str and c == ?" -> balanced(s, i + 1, depth, false, false)
      str -> balanced(s, i + 1, depth, true, false)
      c == ?" -> balanced(s, i + 1, depth, true, false)
      c in [?{, ?[] -> balanced(s, i + 1, depth + 1, false, false)
      c in [?}, ?]] and depth == 1 -> binary_part(s, 0, i + 1)
      c in [?}, ?]] -> balanced(s, i + 1, depth - 1, false, false)
      true -> balanced(s, i + 1, depth, false, false)
    end
  end

  # -- JSON-LD summed up ---------------------------------------------------------------------

  defp summaries(raw) do
    case JSON.decode(raw) do
      {:ok, v} -> v |> items() |> Enum.flat_map(&summary/1)
      _ -> []
    end
  end

  defp items(list) when is_list(list), do: Enum.flat_map(list, &items/1)
  defp items(%{"@graph" => g}), do: items(g)
  defp items(%{} = m), do: [m]
  defp items(_), do: []

  defp summary(%{"@type" => type} = m) do
    name = str(m["name"]) || str(m["headline"])
    type = if is_list(type), do: Enum.join(type, "/"), else: to_string(type)

    parts =
      [
        name && ~s(#{type} "#{name}"),
        price(m["offers"]),
        author(m["author"]),
        str(m["datePublished"]) && "published " <> str(m["datePublished"]),
        rating(m["aggregateRating"])
      ]
      |> Enum.filter(& &1)

    if name, do: [Enum.join(parts, " · ")], else: []
  end

  defp summary(_), do: []

  defp price([o | _]), do: price(o)

  defp price(%{} = o) do
    p = str(o["price"]) || str(o["lowPrice"])
    p && "price " <> String.trim(p <> " " <> (str(o["priceCurrency"]) || ""))
  end

  defp price(_), do: nil

  defp author([a | _]), do: author(a)
  defp author(%{"name" => n}), do: str(n) && "by " <> str(n)
  defp author(n) when is_binary(n), do: "by " <> n
  defp author(_), do: nil

  defp rating(%{"ratingValue" => v}), do: str(v) && "rated " <> str(v)
  defp rating(_), do: nil

  defp str(v) when is_binary(v) and v != "", do: v
  defp str(v) when is_number(v), do: to_string(v)
  defp str(_), do: nil

  # -- reading the JSON -------------------------------------------------------------------------

  def list(%{blobs: []}), do: "the page carries no JSON\n"

  def list(%{blobs: blobs}) do
    blobs
    |> Enum.with_index(1)
    |> Enum.map_join(fn {b, i} -> "#{i}  #{b.name}  #{b.size} bytes\n" end)
  end

  def value(data, n, path) do
    with {:ok, v} <- decoded(data, n), {:ok, v} <- dig(v, path), do: {:ok, show(v)}
  end

  def find(data, n, words) do
    with {:ok, v} <- decoded(data, n) do
      low = words |> String.downcase() |> String.split()

      case v
           |> paths([])
           |> Enum.filter(fn {p, s} ->
             Enum.all?(low, &String.contains?(String.downcase(p <> " " <> s), &1))
           end) do
        [] ->
          {:ok, "nothing in it holds \"#{words}\"\n"}

        hits ->
          {:ok,
           hits
           |> Enum.take(40)
           |> Enum.map_join(fn {p, s} -> "#{p} = #{String.slice(s, 0, 160)}\n" end)}
      end
    end
  end

  defp decoded(%{blobs: blobs}, n) do
    with {i, ""} <- Integer.parse(n),
         %{gz: gz, name: name} <- Enum.at(blobs, i - 1) do
      case JSON.decode(:zlib.gunzip(gz)) do
        {:ok, v} -> {:ok, v}
        _ -> {:error, "#{name} is script, not JSON"}
      end
    else
      _ -> {:error, "no JSON #{n} on the page (data lists them)"}
    end
  end

  defp dig(v, ""), do: {:ok, v}

  defp dig(v, path) do
    path
    |> String.split(".", trim: true)
    |> Enum.reduce_while({:ok, v}, fn key, {:ok, v} ->
      case {v, Integer.parse(key)} do
        {%{} = m, _} when is_map_key(m, key) -> {:cont, {:ok, m[key]}}
        {l, {i, ""}} when is_list(l) and i < length(l) -> {:cont, {:ok, Enum.at(l, i)}}
        _ -> {:halt, {:error, "nothing at #{path} (stopped at #{key})"}}
      end
    end)
  end

  defp show(v) when is_binary(v), do: v <> "\n"
  defp show(v) when is_number(v) or is_boolean(v) or is_nil(v), do: JSON.encode!(v) <> "\n"

  defp show(v) do
    keys =
      if is_map(v),
        do: "keys: " <> Enum.join(Map.keys(v), ", ") <> "\n",
        else: "#{length(v)} items\n"

    json = JSON.encode!(v)

    keys <>
      if(byte_size(json) > 4000, do: String.slice(json, 0, 4000) <> " …\n", else: json <> "\n")
  end

  # every scalar as {path, text}
  defp paths(%{} = m, at), do: Enum.flat_map(m, fn {k, v} -> paths(v, [k | at]) end)

  defp paths(l, at) when is_list(l),
    do: l |> Enum.with_index() |> Enum.flat_map(fn {v, i} -> paths(v, [to_string(i) | at]) end)

  defp paths(v, at),
    do: [{at |> Enum.reverse() |> Enum.join("."), if(is_binary(v), do: v, else: JSON.encode!(v))}]
end

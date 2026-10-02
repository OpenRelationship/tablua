defmodule Moss.Computer.Page.Watch do
  @moduledoc """
  The page as a person watching sees it: kept as one gzipped binary (off the computer's heap) of the page with
  its scripts, frames and `on*` handlers taken out, each control marked `data-moss` by `Page.Controls`. Drawn
  only when watched: unzipped, read again, the fields given what the agent typed, links read against the page.
  A page kept without its copy (an answer kept in history) is drawn from its words.
  """
  import Moss.Computer.Page.Attrs, only: [attr: 2]

  def copy(tree), do: tree |> strip() |> Moss.HTML.to_html() |> :zlib.gzip()

  def html(%{watch: nil} = page) do
    words = page |> Moss.Computer.Page.text() |> Moss.HTML.escape()
    head(page.url, "<html><head></head><body><pre>" <> words <> "</pre></body></html>")
  end

  def html(page) do
    tree = page.watch |> :zlib.gunzip() |> Moss.HTML.parse() |> fill(page.values)
    head(page.url, Moss.HTML.to_html(tree))
  end

  defp head(url, html) do
    base = ~s(<base href="#{Moss.HTML.escape_attr(url)}" target="_blank">)
    String.replace(html, "<head>", "<head>" <> base, global: false)
  end

  defp strip(tree) do
    for node <- tree, keep?(node) do
      case node do
        {t, a, k} -> {t, Enum.reject(a, fn {k, _} -> String.starts_with?(k, "on") end), strip(k)}
        s -> s
      end
    end
  end

  defp keep?({tag, _, _}), do: tag not in ~w(script noscript iframe object embed)
  defp keep?(_), do: true

  defp fill(tree, values) do
    Enum.map(tree, fn
      {tag, a, k} ->
        case Map.fetch(values, attr(a, "data-moss") || "") do
          {:ok, v} -> put(tag, a, k, v)
          :error -> {tag, a, fill(k, values)}
        end

      s ->
        s
    end)
  end

  defp put("input", a, k, v) do
    if Enum.any?(a, &(&1 in [{"type", "checkbox"}, {"type", "radio"}])),
      do:
        {"input", if(v == "on", do: set(a, "checked", "checked"), else: unset(a, "checked")), k},
      else: {"input", set(a, "value", v), k}
  end

  defp put("textarea", a, _k, v), do: {"textarea", a, [v]}
  defp put(tag, a, k, _v), do: {tag, a, k}

  defp set(attrs, name, value), do: [{name, value} | unset(attrs, name)]
  defp unset(attrs, name), do: Enum.reject(attrs, &match?({^name, _}, &1))
end

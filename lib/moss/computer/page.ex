defmodule Moss.Computer.Page do
  @moduledoc """
  A web page as the computer's browser keeps it: parsed once (`Moss.HTML`, in
  Elixir, since the page may be anyone's), then read as `text` (what a reader
  sees, headings marked) and `controls` (links, fields and buttons, each with an
  id the agent names), as the Mac's `ui` tree gives a window. `html(page)` is
  the page again with its scripts taken out and the fields showing what the
  agent typed, for a person watching.

      page = Page.new(url, html)
      page.title; page.text; page.controls   # [%{id: "3", role: "field", name: "Email", form: 1, ...}]
  """
  defstruct [:url, :title, :tree, text: "", controls: [], values: %{}]

  @skip ~w(script style noscript template svg head iframe object embed)
  @block ~w(p div section article header footer main nav aside li ul ol table tr h1 h2 h3 h4 h5 h6 pre blockquote form label dt dd figcaption br hr)

  def new(url, html) do
    tree = Moss.HTML.parse(html)

    labels =
      for {"label", a, k} <- nodes(tree), f = attr(a, "for"), into: %{}, do: {f, words(k, [])}

    {controls, _} = collect(tree, {[], %{n: 0, form: 0, forms: %{}, labels: labels, label: nil}})
    controls = Enum.reverse(controls)

    %__MODULE__{
      url: url,
      title: title(tree) || url,
      tree: tree,
      text: tree |> read([]) |> IO.iodata_to_binary() |> tidy(),
      controls: controls,
      values:
        Map.new(for c <- controls, c.role in ["field", "checkbox", "radio"], do: {c.id, c.value})
    }
  end

  @doc "The control named by its id, its name, its form name, or the first whose name holds the words."
  def control(page, said) do
    low = String.downcase(said)
    shown = Enum.reject(page.controls, &(&1.role == "hidden"))

    Enum.find(shown, &(&1.id == said)) || Enum.find(shown, &(String.downcase(&1.name) == low)) ||
      Enum.find(shown, &(&1.field == said)) ||
      Enum.find(shown, &String.contains?(String.downcase(&1.name), low))
  end

  @doc "The controls as lines: `[3] field \"Email\" = ada@example.com`."
  def outline(page) do
    page.controls
    |> Enum.reject(&(&1.role == "hidden"))
    |> Enum.map_join(fn c ->
      value = Map.get(page.values, c.id)

      shown =
        if c.role == "field" and c.type == "password" and value not in [nil, ""],
          do: "••••",
          else: value

      "[#{c.id}] #{c.role} \"#{c.name}\"" <>
        if(shown not in [nil, ""], do: " = #{shown}", else: "") <> "\n"
    end)
  end

  @doc "The page's html for a watcher: no scripts, the fields holding their values, links resolved."
  def html(page) do
    tree = page.tree |> strip() |> fill(page)
    base = ~s(<base href="#{Moss.HTML.escape_attr(page.url)}" target="_blank">)

    String.replace(Moss.HTML.to_html(tree), "<head>", "<head>" <> base, global: false)
  end

  # -- reading -----------------------------------------------------------------------------------

  defp title(tree) do
    Enum.find_value(nodes(tree), fn
      {"title", _, kids} ->
        kids
        |> Enum.filter(&is_binary/1)
        |> Enum.join()
        |> String.trim()
        |> then(&(&1 != "" && &1))

      _ ->
        nil
    end)
  end

  defp nodes(tree),
    do:
      Enum.flat_map(tree, fn
        {_, _, kids} = n -> [n | nodes(kids)]
        _ -> []
      end)

  defp read(tree, acc) do
    Enum.reduce(tree, acc, fn
      text, acc when is_binary(text) ->
        [acc, String.replace(text, ~r/\s+/, " ")]

      {tag, _, _}, acc when tag in @skip ->
        acc

      {"h" <> n = tag, _, kids}, acc when tag in ~w(h1 h2 h3 h4 h5 h6) ->
        [acc, "\n", String.duplicate("#", String.to_integer(n)), " ", read(kids, []), "\n"]

      {"li", _, kids}, acc ->
        [acc, "\n- ", read(kids, []), "\n"]

      {"img", attrs, _}, acc ->
        case attr(attrs, "alt"),
          do: (
            nil -> acc
            "" -> acc
            alt -> [acc, "[image: ", alt, "]"]
          )

      {tag, _, kids}, acc when tag in @block ->
        [acc, "\n", read(kids, []), "\n"]

      {_, _, kids}, acc ->
        read(kids, acc)

      _, acc ->
        acc
    end)
  end

  defp tidy(text) do
    text
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.chunk_by(&(&1 == ""))
    |> Enum.map(fn
      ["" | _] -> [""]
      l -> l
    end)
    |> List.flatten()
    |> Enum.join("\n")
    |> String.trim()
  end

  # -- controls ----------------------------------------------------------------------------------

  defp collect(tree, acc) do
    Enum.reduce(tree, acc, fn
      {tag, _, _}, acc when tag in @skip ->
        acc

      {"form", attrs, kids}, {cs, st} ->
        n = st.form + 1

        form =
          case hx(attrs) do
            {method, url} ->
              %{action: url, method: method, hx: true}

            nil ->
              %{
                action: attr(attrs, "action") || "",
                method: String.upcase(attr(attrs, "method") || "GET"),
                hx: false
              }
          end

        {cs, st} = collect(kids, {cs, %{st | form: n, forms: Map.put(st.forms, n, form)}})
        {cs, %{st | form: 0, forms: st.forms}}

      {"label", _attrs, kids}, {cs, st} ->
        {cs, st2} = collect(kids, {cs, %{st | label: words(kids, [])}})
        {cs, %{st2 | label: st.label}}

      {"a", attrs, kids}, acc ->
        case {hx(attrs), attr(attrs, "href")} do
          {{"GET", url}, _} ->
            add(acc, %{role: "link", name: words(kids, attrs), href: url})

          {{_, _} = req, _} ->
            add(acc, %{role: "button", name: words(kids, attrs), type: "button", hx: req})

          {nil, nil} ->
            acc

          {nil, href} ->
            add(acc, %{role: "link", name: words(kids, attrs), href: href})
        end

      {"button", attrs, kids}, acc ->
        add(acc, %{
          role: "button",
          name: words(kids, attrs),
          type: attr(attrs, "type") || "submit",
          field: attr(attrs, "name"),
          value: attr(attrs, "value"),
          hx: hx(attrs)
        })

      {"input", attrs, _}, acc ->
        input(attr(attrs, "type") || "text", attrs, acc)

      {"textarea", attrs, kids}, acc ->
        add(acc, %{
          role: "field",
          name: label(attrs, acc),
          type: "textarea",
          field: attr(attrs, "name"),
          value: Enum.join(Enum.filter(kids, &is_binary/1))
        })

      {"select", attrs, kids}, acc ->
        opts = for {"option", oa, ok} <- nodes(kids), do: attr(oa, "value") || words(ok, oa)

        add(acc, %{
          role: "field",
          name: label(attrs, acc),
          type: "select",
          field: attr(attrs, "name"),
          value: List.first(opts, ""),
          options: opts
        })

      {_, _, kids}, acc ->
        collect(kids, acc)

      _, acc ->
        acc
    end)
  end

  defp input(type, attrs, acc) when type in ["submit", "button", "image", "reset"],
    do:
      add(acc, %{
        role: "button",
        name:
          attr(attrs, "value") ||
            if(label(attrs, acc) == "", do: "Submit", else: label(attrs, acc)),
        type: type,
        field: attr(attrs, "name"),
        value: attr(attrs, "value")
      })

  defp input("hidden", attrs, acc),
    do:
      add(acc, %{
        role: "hidden",
        name: attr(attrs, "name") || "",
        field: attr(attrs, "name"),
        value: attr(attrs, "value") || ""
      })

  defp input(type, attrs, acc) when type in ["checkbox", "radio"],
    do:
      add(acc, %{
        role: if(type == "radio", do: "radio", else: "checkbox"),
        name: label(attrs, acc),
        type: type,
        field: attr(attrs, "name"),
        value: if(attr(attrs, "checked"), do: "on", else: ""),
        on: attr(attrs, "value") || "on"
      })

  defp input(type, attrs, acc),
    do:
      add(acc, %{
        role: "field",
        name: label(attrs, acc),
        type: type,
        field: attr(attrs, "name"),
        value: attr(attrs, "value") || ""
      })

  defp add({cs, st}, c) do
    n = st.n + 1

    c =
      Map.merge(
        %{
          id: to_string(n),
          form: st.form,
          form_info: Map.get(st.forms, st.form),
          type: nil,
          field: nil,
          value: nil,
          hx: nil
        },
        c
      )

    {[c | cs], %{st | n: n}}
  end

  # what a person reads as the control's name: aria-label, a <label for>, the <label> around it, then its own words
  defp label(attrs, {_, st}) do
    found = attr(attrs, "aria-label") || Map.get(st.labels, attr(attrs, "id")) || st.label
    found = found && String.trim(String.trim_trailing(String.trim(found), ":"))

    if found in [nil, ""],
      do: attr(attrs, "placeholder") || attr(attrs, "name") || attr(attrs, "id") || "",
      else: found
  end

  defp words(kids, attrs) do
    text =
      kids |> read([]) |> IO.iodata_to_binary() |> String.replace(~r/\s+/, " ") |> String.trim()

    if text == "", do: attr(attrs, "aria-label") || attr(attrs, "title") || "", else: text
  end

  defp attr(attrs, name), do: Enum.find_value(attrs, fn {k, v} -> k == name && v end)

  # an htmx request an element makes: {method, url}
  defp hx(attrs) do
    Enum.find_value(~w(get post put patch delete), fn m ->
      if url = attr(attrs, "hx-" <> m), do: {String.upcase(m), url}
    end)
  end

  # -- for a watcher -----------------------------------------------------------------------------

  defp strip(tree) do
    for node <- tree,
        keep?(node),
        do:
          case(node,
            do: (
              {t, a, k} ->
                {t, Enum.reject(a, fn {k, _} -> String.starts_with?(k, "on") end), strip(k)}

              s ->
                s
            )
          )
  end

  defp keep?({tag, _, _}), do: tag not in ~w(script noscript iframe object embed)
  defp keep?(_), do: true

  # the n-th control in document order gets its value back, as collect/2 numbered them
  defp fill(tree, page) do
    {tree, _} = fill(tree, page, 0)
    tree
  end

  defp fill(tree, page, n) do
    Enum.map_reduce(tree, n, fn
      {tag, a, k}, n when tag in ~w(a button input textarea select) ->
        n = if tag == "a" and not link?(a), do: n, else: n + 1
        value = Map.get(page.values, to_string(n))

        cond do
          tag == "input" and value != nil and box?(a) ->
            {{tag, if(value == "on", do: set(a, "checked", "checked"), else: unset(a, "checked")),
              k}, n}

          tag == "input" and value != nil ->
            {{tag, set(a, "value", value), k}, n}

          tag == "textarea" and value != nil ->
            {{tag, a, [value]}, n}

          true ->
            {k2, n} = fill(k, page, n)
            {{tag, a, k2}, n}
        end

      {tag, _, _} = node, n when tag in @skip ->
        {node, n}

      {tag, a, k}, n ->
        {k, n} = fill(k, page, n)
        {{tag, a, k}, n}

      s, n ->
        {s, n}
    end)
  end

  defp link?(attrs),
    do: Enum.any?(attrs, fn {k, _} -> k in ~w(href hx-get hx-post hx-put hx-patch hx-delete) end)

  defp set(attrs, name, value), do: [{name, value} | unset(attrs, name)]
  defp unset(attrs, name), do: Enum.reject(attrs, &match?({^name, _}, &1))
  defp box?(attrs), do: Enum.any?(attrs, &(&1 in [{"type", "checkbox"}, {"type", "radio"}]))
end

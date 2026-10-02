defmodule Moss.Computer.Page.Controls do
  @moduledoc """
  A page's controls as an accessibility tree gives them: links, buttons, fields, boxes, and any element whose
  `role` makes it one (button, link, checkbox, radio, switch, tab, menuitem, option, textbox, searchbox,
  combobox). Each is named as a screen reader names it (`aria-labelledby`, `aria-label`, its `<label>`, its own
  words, `title`, `placeholder`), described by `aria-describedby`, and carries its states (checked, selected,
  expanded or collapsed, pressed, required, disabled), its region and section (as `Page.Read` counts them).
  Hidden things are not controls.

  `collect/1` returns the controls and the tree with each control's element marked `data-moss="<id>"`, so the
  watcher's copy can show what the agent typed in the right field.
  """
  import Moss.Computer.Page.Attrs, only: [attr: 2, hidden?: 1, words: 1]
  alias Moss.Computer.Page.{Attrs, Control}

  @roles %{
    "button" => "button",
    "link" => "link",
    "checkbox" => "checkbox",
    "switch" => "checkbox",
    "menuitemcheckbox" => "checkbox",
    "radio" => "radio",
    "menuitemradio" => "radio",
    "tab" => "tab",
    "menuitem" => "menuitem",
    "option" => "option",
    "textbox" => "field",
    "searchbox" => "field",
    "combobox" => "field"
  }

  def collect(tree) do
    nodes = all(tree)

    labels =
      for {"label", a, k} <- nodes, f = attr(a, "for"), into: %{}, do: {f, words(k)}

    wanted =
      for {_, a, _} <- nodes,
          k <- ["aria-labelledby", "aria-describedby"],
          v = attr(a, k),
          id <- String.split(v),
          into: MapSet.new(),
          do: id

    refs =
      for {_, a, k} <- nodes,
          id = attr(a, "id"),
          MapSet.member?(wanted, id),
          into: %{},
          do: {id, words(k)}

    st = %{n: 0, form: 0, forms: %{}, label: nil, labels: labels, refs: refs, section: 0, out: []}
    {tree, st} = walk(tree, %{region: :body, sectioning: false}, st)
    {Enum.reverse(st.out), tree}
  end

  defp all(tree),
    do:
      Enum.flat_map(tree, fn
        {_, _, k} = n -> [n | all(k)]
        _ -> []
      end)

  defp walk(nodes, ctx, st), do: Enum.map_reduce(nodes, st, &node(&1, ctx, &2))

  defp node({tag, attrs, kids} = n, ctx, st) do
    cond do
      tag in Attrs.skip() or hidden?(attrs) ->
        {n, st}

      true ->
        st =
          if Attrs.heading(tag, attrs) && words(kids) != "",
            do: %{st | section: st.section + 1},
            else: st

        element(tag, attrs, kids, ctx, st)
    end
  end

  defp node(other, _ctx, st), do: {other, st}

  defp element("form", attrs, kids, ctx, st) do
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

    {kids, st2} =
      walk(kids, Attrs.enter("form", attrs, ctx), %{
        st
        | form: n,
          forms: Map.put(st.forms, n, form)
      })

    {{"form", attrs, kids}, %{st2 | form: 0}}
  end

  defp element("label", attrs, kids, ctx, st) do
    {kids, st2} = walk(kids, ctx, %{st | label: words(kids)})
    {{"label", attrs, kids}, %{st2 | label: st.label}}
  end

  defp element("a", attrs, kids, ctx, st) do
    case {hx(attrs), attr(attrs, "href"), attr(attrs, "role")} do
      {{"GET", url}, _, _} ->
        add("a", attrs, kids, ctx, st, %{role: "link", href: url})

      {{_, _} = req, _, _} ->
        add("a", attrs, kids, ctx, st, %{role: "button", type: "button", hx: req})

      {nil, nil, role} when is_map_key(@roles, role) ->
        by_role("a", attrs, kids, ctx, st)

      {nil, nil, _} ->
        descend("a", attrs, kids, ctx, st)

      {nil, href, _} ->
        add("a", attrs, kids, ctx, st, %{role: "link", href: href})
    end
  end

  defp element("button", attrs, kids, ctx, st) do
    add("button", attrs, kids, ctx, st, %{
      role: "button",
      type: attr(attrs, "type") || "submit",
      field: attr(attrs, "name"),
      value: attr(attrs, "value"),
      hx: hx(attrs),
      vals: vals(attrs)
    })
  end

  defp element("input", attrs, kids, ctx, st),
    do: input(attr(attrs, "type") || "text", attrs, kids, ctx, st)

  defp element("textarea", attrs, kids, ctx, st) do
    add("textarea", attrs, kids, ctx, st, %{
      role: "field",
      type: "textarea",
      field: attr(attrs, "name"),
      value: Enum.join(Enum.filter(kids, &is_binary/1))
    })
  end

  defp element("select", attrs, kids, ctx, st) do
    opts = for {"option", oa, ok} <- all(kids), do: attr(oa, "value") || words(ok)

    add("select", attrs, kids, ctx, st, %{
      role: "field",
      type: "select",
      field: attr(attrs, "name"),
      value: List.first(opts, ""),
      options: opts
    })
  end

  defp element(tag, attrs, kids, ctx, st) do
    if Map.has_key?(@roles, attr(attrs, "role")),
      do: by_role(tag, attrs, kids, ctx, st),
      else: descend(tag, attrs, kids, ctx, st)
  end

  defp descend(tag, attrs, kids, ctx, st) do
    {kids, st} = walk(kids, Attrs.enter(tag, attrs, ctx), st)
    {{tag, attrs, kids}, st}
  end

  defp by_role(tag, attrs, kids, ctx, st) do
    role = Map.fetch!(@roles, attr(attrs, "role"))
    value = if role == "field", do: words(kids), else: nil

    add(tag, attrs, kids, ctx, st, %{
      role: role,
      type: attr(attrs, "role"),
      value: value,
      href: attr(attrs, "href")
    })
  end

  defp input(type, attrs, kids, ctx, st) when type in ["submit", "button", "image", "reset"] do
    fallback =
      attr(attrs, "value") || if(type == "image", do: attr(attrs, "alt"), else: nil) || "Submit"

    add(
      "input",
      attrs,
      kids,
      ctx,
      st,
      %{role: "button", type: type, field: attr(attrs, "name"), value: attr(attrs, "value")},
      fallback
    )
  end

  defp input("hidden", attrs, kids, ctx, st) do
    add(
      "input",
      attrs,
      kids,
      ctx,
      st,
      %{role: "hidden", field: attr(attrs, "name"), value: attr(attrs, "value") || ""},
      attr(attrs, "name") || ""
    )
  end

  defp input(type, attrs, kids, ctx, st) when type in ["checkbox", "radio"] do
    add("input", attrs, kids, ctx, st, %{
      role: type,
      type: type,
      field: attr(attrs, "name"),
      value: if(attr(attrs, "checked"), do: "on", else: ""),
      on: attr(attrs, "value") || "on"
    })
  end

  defp input(type, attrs, kids, ctx, st) do
    add("input", attrs, kids, ctx, st, %{
      role: "field",
      type: type,
      field: attr(attrs, "name"),
      value: attr(attrs, "value") || ""
    })
  end

  defp add(tag, attrs, kids, ctx, st, fields, fallback \\ nil) do
    n = st.n + 1
    id = to_string(n)
    field? = fields.role in ["field", "checkbox", "radio"] and tag in ~w(input textarea select)

    c =
      struct(
        Control,
        Map.merge(fields, %{
          id: id,
          name: name(attrs, kids, field?, st, fallback),
          desc: refs(attrs, "aria-describedby", st),
          states: states(attrs),
          form: st.form,
          form_info: Map.get(st.forms, st.form),
          region: ctx.region,
          section: st.section
        })
      )

    {{tag, [{"data-moss", id} | attrs], kids}, %{st | n: n, out: [c | st.out]}}
  end

  # the accessible name, in the order a screen reader looks
  defp name(attrs, kids, field?, st, fallback) do
    label = if field?, do: Map.get(st.labels, attr(attrs, "id")) || st.label, else: nil
    own = if field?, do: nil, else: words(kids)

    [
      refs(attrs, "aria-labelledby", st),
      attr(attrs, "aria-label"),
      label,
      own,
      attr(attrs, "title"),
      attr(attrs, "placeholder"),
      fallback,
      field? && (attr(attrs, "name") || attr(attrs, "id"))
    ]
    |> Enum.find_value("", fn
      v when is_binary(v) ->
        (t = v |> String.trim() |> String.trim_trailing(":") |> String.trim()) != "" && t

      _ ->
        nil
    end)
  end

  defp refs(attrs, key, st) do
    case attr(attrs, key) do
      nil ->
        nil

      ids ->
        ids
        |> String.split()
        |> Enum.map(&Map.get(st.refs, &1, ""))
        |> Enum.join(" ")
        |> String.trim()
        |> nil_if_empty()
    end
  end

  defp nil_if_empty(""), do: nil
  defp nil_if_empty(s), do: s

  defp states(attrs) do
    on = &(attr(attrs, &1) == "true")

    [
      on.("aria-checked") && "checked",
      attr(attrs, "aria-checked") == "mixed" && "mixed",
      on.("aria-selected") && "selected",
      on.("aria-expanded") && "expanded",
      attr(attrs, "aria-expanded") == "false" && "collapsed",
      on.("aria-pressed") && "pressed",
      (attr(attrs, "required") != nil or on.("aria-required")) && "required",
      (attr(attrs, "disabled") != nil or on.("aria-disabled")) && "disabled"
    ]
    |> Enum.filter(&is_binary/1)
  end

  # hx-vals: a JSON object of strings, numbers and booleans, as {name, text}; anything else sends nothing
  defp vals(attrs) do
    with s when is_binary(s) <- attr(attrs, "hx-vals"),
         {:ok, %{} = m} <- Jason.decode(s) do
      for {k, v} <- Enum.sort(m), is_binary(v) or is_number(v) or is_boolean(v), do: {k, to_string(v)}
    else
      _ -> []
    end
  end

  # an htmx request an element makes: {method, url}
  defp hx(attrs) do
    Enum.find_value(~w(get post put patch delete), fn m ->
      if url = attr(attrs, "hx-" <> m), do: {String.upcase(m), url}
    end)
  end
end

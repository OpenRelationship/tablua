defmodule Moss.Computer.Browser do
  @moduledoc """
  The computer's browser, headless: pages fetched by `Computer.Net`, kept as
  `Computer.Page`s, one per tab, and drawn only when a person watches. The shell
  drives it:

      open <address>        a page in a new tab: its title, words and controls
      page                  the front page's words      ui      its controls, each with an id
      click <id|words>      follows a link, or presses a button (a submit button sends its form)
      type <id|words> <text>  puts text in a field      submit [id|words]  sends a form
      back                  the page before             tabs    the open tabs

  `open app` opens the computer's own app (`/home/app.lua`, at http://app/), as
  its person sees it. htmx counts: an element's hx-get is a link, hx-post (and
  put, patch, delete) on a button or form sends the request and then shows the
  page again, as the app's own page would after its swap.

  A password field is the person's: the browser never types into one. Page
  scripts do not run yet; a page drawn only by its scripts reads as nearly empty.
  """
  alias Moss.Computer.{Net, Page, Script}

  @app "http://app/"

  @names ~w(open page ui click type submit back tabs)
  def names, do: @names

  def new, do: %{tabs: [], front: nil}

  def front(%{browser: %{tabs: tabs, front: n}}) when is_integer(n), do: Enum.at(tabs, n)
  def front(_), do: nil

  def run("open", ["app" <> rest | _], _stdin, state)
      when rest == "" or binary_part(rest, 0, 1) == "/",
      do: go(state, @app <> String.trim_leading(rest, "/"), :new_tab)

  def run("open", [url | _], _stdin, state), do: go(state, url, :new_tab)
  def run("open", [], _stdin, state), do: {2, "", "open: needs an address\n", state}

  def run("tabs", _, _stdin, state),
    do:
      {0,
       state.browser.tabs
       |> Enum.with_index()
       |> Enum.map_join(fn {t, i} ->
         "#{if i == state.browser.front, do: "*", else: " "} #{i + 1} #{t.page.title} — #{t.page.url}\n"
       end), "", state}

  def run(name, args, _stdin, state) do
    case front(state) do
      nil -> {1, "", "#{name}: no page is open (open <address>)\n", state}
      tab -> on_page(name, args, tab, state)
    end
  end

  defp on_page("page", _, tab, state), do: {0, tab.page.text <> "\n", "", state}
  defp on_page("ui", _, tab, state), do: {0, Page.outline(tab.page), "", state}

  defp on_page("back", _, tab, state) do
    case tab.history do
      [prev | older] ->
        {0, summary(prev), "", put_tab(state, %{tab | page: prev, history: older})}

      [] ->
        {1, "", "back: this is the first page in the tab\n", state}
    end
  end

  defp on_page("click", [said | _], tab, state) do
    case Page.control(tab.page, said) do
      %{role: "link", href: href} ->
        go(state, resolve(tab.page, href), :same_tab)

      %{role: "button", hx: {"GET", url}} ->
        go(state, resolve(tab.page, url), :same_tab)

      %{role: "button", hx: {method, url}} = c ->
        pairs = if c.form > 0, do: form_pairs(tab.page, c), else: own_pair(c)
        act(state, tab, method, resolve(tab.page, url), pairs)

      %{role: "button", type: t} = c when t in ["submit", "image"] ->
        send_form(state, tab, c)

      %{role: box} = c when box in ["checkbox", "radio"] ->
        {0, "", "", put_tab(state, %{tab | page: toggle(tab.page, c)})}

      %{role: "button"} = c ->
        {0, "pressed \"#{c.name}\" (its script does not run here)\n", "", state}

      %{} = c ->
        {1, "", "click: [#{c.id}] is a #{c.role}; type into it instead\n", state}

      nil ->
        {1, "", "click: nothing on the page is \"#{said}\" (ui lists the controls)\n", state}
    end
  end

  defp on_page("type", [said | words], tab, state) when words != [] do
    case Page.control(tab.page, said) do
      %{role: "field", type: "password"} ->
        {1, "", "type: a password is the person's own to type; it was left empty\n", state}

      %{role: "field"} = c ->
        page = %{tab.page | values: Map.put(tab.page.values, c.id, Enum.join(words, " "))}

        {0, "[#{c.id}] \"#{c.name}\" = #{Enum.join(words, " ")}\n", "",
         put_tab(state, %{tab | page: page})}

      nil ->
        {1, "", "type: nothing on the page is \"#{said}\"\n", state}

      c ->
        {1, "", "type: [#{c.id}] is a #{c.role}, not a field\n", state}
    end
  end

  defp on_page("submit", args, tab, state) do
    c =
      if args == [],
        do: Enum.find(tab.page.controls, &(&1.form > 0)),
        else: Page.control(tab.page, hd(args))

    if c && c.form > 0,
      do: send_form(state, tab, c),
      else: {1, "", "submit: no form on the page\n", state}
  end

  defp on_page(name, _args, _tab, state), do: {2, "", "#{name}: needs more (see help)\n", state}

  # -- going places ------------------------------------------------------------------------------

  defp go(state, url, where, opts \\ []) do
    case fetch(state, url, opts) do
      {:ok, %{status: status, body: body, url: at}} ->
        page = Page.new(at, if(is_binary(body), do: body, else: ""))
        state = place(state, page, where)

        {if(status >= 400, do: 22, else: 0), summary(page),
         if(status >= 400, do: "the page answered #{status}\n", else: ""), state}

      {:error, why} ->
        {6, "", "open: #{why}\n", state}
    end
  end

  defp place(state, page, :new_tab) do
    tabs = state.browser.tabs ++ [%{page: page, history: []}]
    %{state | browser: %{tabs: tabs, front: length(tabs) - 1}}
  end

  defp place(state, page, :same_tab) do
    tab = front(state)
    put_tab(state, %{tab | page: page, history: [tab.page | tab.history]})
  end

  defp put_tab(state, tab),
    do: %{
      state
      | browser: %{
          state.browser
          | tabs: List.replace_at(state.browser.tabs, state.browser.front, tab)
        }
    }

  defp send_form(state, tab, pressed) do
    page = tab.page
    form = pressed.form_info || %{action: "", method: "GET", hx: false}
    pairs = form_pairs(page, pressed)
    action = resolve(page, if(form.action == "", do: page.url, else: form.action))
    query = URI.encode_query(pairs)

    if form.hx and form.method != "GET" do
      act(state, tab, form.method, action, pairs)
    else
      send_plain(state, form, action, query)
    end
  end

  defp form_pairs(page, pressed) do
    for c <- page.controls,
        c.form == pressed.form,
        c.field not in [nil, ""],
        c.role != "button" or c.id == pressed.id,
        value = form_value(page, c),
        value != nil,
        do: {c.field, value}
  end

  defp own_pair(%{field: f, value: v}) when f not in [nil, ""], do: [{f, v || ""}]
  defp own_pair(_), do: []

  # an htmx request: sent, then the page shown again (or where the app sends it)
  defp act(state, tab, method, url, pairs) do
    opts = [
      method: method,
      body: URI.encode_query(pairs),
      headers: [{"content-type", "application/x-www-form-urlencoded"}, {"hx-request", "true"}]
    ]

    case fetch(state, url, opts) do
      {:ok, %{status: status}} when status >= 400 ->
        {22, "", "#{method} #{url} answered #{status}\n", state}

      {:ok, %{headers: %{"hx-redirect" => to}}} ->
        go(state, resolve(tab.page, to), :same_tab)

      {:ok, _} ->
        case fetch(state, tab.page.url, []) do
          {:ok, %{body: body, url: at}} ->
            page = Page.new(at, if(is_binary(body), do: body, else: ""))
            {0, summary(page), "", put_tab(state, %{tab | page: page})}

          {:error, why} ->
            {6, "", "open: #{why}\n", state}
        end

      {:error, why} ->
        {6, "", "#{method}: #{why}\n", state}
    end
  end

  # the computer's own app answers http://app/ here, from its disk; everything else is the web
  defp fetch(state, @app <> _ = url, opts), do: fetch_app(state, url, opts, 5)
  defp fetch(_state, url, opts), do: Net.get(url, opts)

  defp fetch_app(state, url, opts, hops) do
    uri = URI.parse(url)
    method = opts[:method] || "GET"
    form = if method == "GET", do: %{}, else: URI.decode_query(opts[:body] || "")

    headers =
      for {k, v} <- opts[:headers] || [], String.starts_with?(k, "hx-"), into: %{}, do: {k, v}

    req =
      Moss.Computer.App.request(
        method,
        uri.path || "/",
        URI.decode_query(uri.query || ""),
        form,
        headers
      )

    {status, headers, body, _err} = Script.serve(req, state)

    case headers do
      %{"location" => to} when status in 301..308 and hops > 0 ->
        fetch_app(state, URI.to_string(URI.merge(@app, to)), [], hops - 1)

      _ ->
        {:ok, %{status: status, body: body, url: url, headers: headers}}
    end
  end

  defp send_plain(state, form, action, query) do
    if form.method == "POST" do
      go(state, action, :same_tab,
        method: "POST",
        body: query,
        headers: [{"content-type", "application/x-www-form-urlencoded"}]
      )
    else
      uri = URI.parse(action)
      go(state, URI.to_string(%{uri | query: query}), :same_tab)
    end
  end

  defp form_value(page, %{role: box} = c) when box in ["checkbox", "radio"],
    do: if(Map.get(page.values, c.id) == "on", do: c.on)

  defp form_value(page, c), do: Map.get(page.values, c.id, c.value) || ""

  # a radio button turns the others of its name off; a checkbox flips
  defp toggle(page, %{type: "radio"} = c) do
    off = for o <- page.controls, o.type == "radio", o.field == c.field, into: %{}, do: {o.id, ""}
    %{page | values: page.values |> Map.merge(off) |> Map.put(c.id, "on")}
  end

  defp toggle(page, c),
    do: %{page | values: Map.update(page.values, c.id, "on", &if(&1 == "on", do: "", else: "on"))}

  # an app's page is read against the app's root, as its <base> has the person's browser read it
  defp resolve(%{url: @app <> _}, href), do: @app |> URI.merge(href) |> URI.to_string()
  defp resolve(page, href), do: page.url |> URI.merge(href) |> URI.to_string()

  defp summary(page) do
    words =
      if String.length(page.text) > 1500,
        do: String.slice(page.text, 0, 1500) <> " …(page shows the rest)",
        else: page.text

    "#{page.title}\n#{page.url}\n\n#{words}\n\n#{Page.outline(page)}"
  end
end

defmodule Moss.Computer.Browser.Nav do
  @moduledoc """
  How the browser gets a page: fetched by `Computer.Net` as a browser asks (its headers, gzip, the computer's
  cookie jar, a page read to 5 MB), its bytes made UTF-8 (`Computer.Charset`), a short `<meta refresh>` followed,
  `Referer` sent on a link (the origin alone across sites, nothing from https to http) and `Origin` on a form.
  The computer's own app answers `http://app/` from its disk. `load/1` fetches a woken tab's page again.
  """
  alias Moonflower.{Charset, Page}
  alias Moss.Computer.{Look, Net, Script}
  alias Moss.Computer.Browser.Tabs
  alias Moonflower.Page.Parts

  @app "http://app/"
  @max 5 * 1024 * 1024
  @refreshes 3

  @doc "Opens `url`: where is `:new_tab` or `:same_tab`; `from` is the page a link or form was on."
  def go(state, url, where, opts \\ [], from \\ nil, refreshes \\ @refreshes) do
    opts = Keyword.update(opts, :headers, referer(from, url), &(&1 ++ referer(from, url)))

    case fetch(state, url, opts) do
      {:ok, r, state} ->
        page = page(r, opts, state)

        if page.refresh && refreshes > 0 do
          go(state, resolve(page, page.refresh), where, [], nil, refreshes - 1)
        else
          {state, note} =
            if where == :new_tab, do: Tabs.open(state, page), else: {Tabs.go(state, page), ""}

          err = if r.status >= 400, do: "the page answered #{r.status}\n", else: ""
          {if(r.status >= 400, do: 22, else: 0), Parts.summary(page) <> note, err, state}
        end

      {:error, why} ->
        {6, "", "open: #{why}\n", state}
    end
  end

  @doc "The front tab with its page, fetched again if the computer slept since: `{:ok, tab, state}`."
  def load(state) do
    case Tabs.front(state) do
      %{page: nil} = tab ->
        case fetch(state, tab.url, []) do
          {:ok, r, state} ->
            page = page(r, [], state)
            ids = MapSet.new(page.controls, & &1.id)

            values =
              for {id, v} <- tab.values, MapSet.member?(ids, id), into: page.values, do: {id, v}

            tab = %{tab | page: %{page | values: values}}
            {:ok, tab, Tabs.put(state, tab)}

          {:error, why} ->
            {:error, why}
        end

      tab ->
        {:ok, tab, state}
    end
  end

  defp page(r, opts, state) do
    {html, note} =
      Charset.decode(if(is_binary(r.body), do: r.body, else: ""), content_type(r.headers))

    cut = Map.get(r, :cut) && "(read to #{size(max())}; the rest of the page was not read)"
    notes = Enum.filter([note, cut], & &1)

    # the computer's own app is laid out as its person sees it (Computer.Look); the web is read as it comes
    page =
      case r.url do
        @app <> _ -> Look.page(r.url, html, notes, Tabs.screen(state))
        _ -> Page.new(r.url, html, notes)
      end

    page = %{page | base: Map.get(r, :base)}
    if Keyword.get(opts, :method, "GET") != "GET", do: %{page | answer: true}, else: page
  end

  # 5 MB, or the node's own limit when it is lower (config `net_max_bytes`)
  defp max, do: min(@max, Application.get_env(:moss, :net_max_bytes, @max))

  defp size(n) when rem(n, 1_048_576) == 0, do: "#{div(n, 1_048_576)} MB"
  defp size(n), do: "#{n} bytes"

  defp content_type(%{} = h) do
    case Map.get(h, "content-type") do
      [ct | _] -> ct
      ct when is_binary(ct) -> ct
      _ -> nil
    end
  end

  # the computer's own app answers http://app/ here, from its disk; everything else is the web
  def fetch(state, @app <> _ = url, opts) do
    case fetch_app(state, url, opts, 5) do
      {:ok, r} -> {:ok, r, state}
      e -> e
    end
  end

  def fetch(state, url, opts) do
    opts =
      Keyword.merge(opts, browser: true, cut: true, max: max(), cookies: state.browser.cookies)

    case Net.get(url, opts) do
      {:ok, r} -> {:ok, r, put_in(state.browser.cookies, r.cookies)}
      e -> e
    end
  end

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

    # `look` asks for each element's line in the page's source (Computer.Look); no person's request can
    req = if opts[:lines], do: Map.put(req, "lines", true), else: req

    {status, headers, body, _err} = Script.serve(req, state)
    html? = headers |> Map.get("content-type", "text/html") |> String.starts_with?("text/html")
    body = if html?, do: Moss.Computer.Clean.html(body), else: body

    case headers do
      %{"location" => to} when status in 301..308 and hops > 0 ->
        fetch_app(state, URI.to_string(URI.merge(@app, to)), Keyword.take(opts, [:lines]), hops - 1)

      _ ->
        # an app's page reads its addresses against the app's root, as its <base> has the person's browser do
        base = if app = headers["x-moss-app"], do: @app <> app <> "/"
        {:ok, %{status: status, body: body, url: url, headers: headers, base: base}}
    end
  end

  # -- forms -------------------------------------------------------------------------------------

  def send_form(state, tab, pressed) do
    page = tab.page
    form = pressed.form_info || %{action: "", method: "GET", hx: false}
    pairs = form_pairs(page, pressed)
    action = resolve(page, if(form.action == "", do: page.url, else: form.action))

    cond do
      form.hx and form.method != "GET" ->
        act(state, tab, form.method, action, pairs)

      form.method == "POST" ->
        go(
          state,
          action,
          :same_tab,
          [
            method: "POST",
            body: URI.encode_query(pairs),
            headers: [{"content-type", "application/x-www-form-urlencoded"} | origin(page)]
          ],
          page
        )

      true ->
        uri = URI.parse(action)
        go(state, URI.to_string(%{uri | query: URI.encode_query(pairs)}), :same_tab, [], page)
    end
  end

  def form_pairs(page, pressed) do
    for c <- page.controls,
        c.form == pressed.form,
        c.field not in [nil, ""],
        c.role != "button" or c.id == pressed.id,
        value = form_value(page, c),
        value != nil,
        do: {c.field, value}
  end

  def own_pair(%{field: f, value: v}) when f not in [nil, ""], do: [{f, v || ""}]
  def own_pair(_), do: []

  # an htmx request: sent, then the page shown again (or where the app sends it)
  def act(state, tab, method, url, pairs) do
    opts = [
      method: method,
      body: URI.encode_query(pairs),
      headers: [
        {"content-type", "application/x-www-form-urlencoded"},
        {"hx-request", "true"} | origin(tab.page)
      ]
    ]

    case fetch(state, url, opts) do
      {:ok, %{status: status}, state} when status >= 400 ->
        {22, "", "#{method} #{url} answered #{status}\n", state}

      {:ok, %{headers: %{"hx-redirect" => to}}, state} ->
        go(state, resolve(tab.page, hx_to(to)), :same_tab, [], tab.page)

      {:ok, _, state} ->
        case fetch(state, tab.page.url, []) do
          {:ok, r, state} ->
            page = page(r, [], state)
            {0, Parts.summary(page), "", Tabs.put(state, %{tab | page: page, ui_at: nil})}

          {:error, why} ->
            {6, "", "open: #{why}\n", state}
        end

      {:error, why} ->
        {6, "", "#{method}: #{why}\n", state}
    end
  end

  defp hx_to([to | _]), do: to
  defp hx_to(to), do: to

  defp form_value(page, %{role: box} = c) when box in ["checkbox", "radio"],
    do: if(Map.get(page.values, c.id) == "on", do: c.on)

  defp form_value(page, c), do: Map.get(page.values, c.id, c.value) || ""

  # -- addresses and where a request comes from ----------------------------------------------------

  # an app's page is read against the app's root, as its <base> has the person's browser read it
  def resolve(%{base: base}, href) when is_binary(base),
    do: base |> URI.merge(href) |> URI.to_string()

  def resolve(%{url: @app <> _}, href), do: @app |> URI.merge(href) |> URI.to_string()
  def resolve(page, href), do: page.url |> URI.merge(href) |> URI.to_string()

  # strict-origin-when-cross-origin, a browser's default
  defp referer(nil, _to), do: []
  defp referer(%{url: @app <> _}, _to), do: []

  defp referer(%{url: from}, to) do
    f = URI.parse(from)
    t = URI.parse(to)

    cond do
      f.scheme == "https" and t.scheme == "http" ->
        []

      {f.scheme, f.host, f.port} == {t.scheme, t.host, t.port} ->
        [{"referer", URI.to_string(%{f | fragment: nil})}]

      true ->
        [{"referer", origin_of(f) <> "/"}]
    end
  end

  defp origin(%{url: @app <> _}), do: []
  defp origin(%{url: url}), do: [{"origin", origin_of(URI.parse(url))}]

  defp origin_of(%URI{scheme: s, host: h, port: p}) do
    if {s, p} in [{"http", 80}, {"https", 443}], do: "#{s}://#{h}", else: "#{s}://#{h}:#{p}"
  end
end

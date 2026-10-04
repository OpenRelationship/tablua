defmodule Moss.Computer.App do
  @moduledoc """
  The computer's app, as a browser gets it: the `.lui` page at a request's path
  answers it (`Moss.Computer.Pages`, `Moss.Computer.Script.serve/2`), and goes
  out as HTML the person's browser draws, with htmx as its only script.

  The page is the agent's writing, so nothing in it runs as code. It is held
  to Shroomi's policy (`Moss.Computer.Clean`); the only scripts allowed are
  Shroomi's pinned assets, served by Moss at /shroomi/; an app answers only in
  types no browser runs as script (sent with `nosniff`); and its requests and
  forms reach no path but the app's own. `base` is where the app lives (for a
  person, `/computers/<id>/app/`); the page gets a `<base>` there, so its
  relative links and hx- paths stay inside it.
  """
  alias Moss.Computer.Clean

  @help """

  Pages: each is a .lui file in ui/, served at its path: /home/ui/index.lui at /, apps/plants/ui/index.lui at
  /plants/ and apps/plants/ui/list.lui at /plants/list. HTML with Lua in it:

    <lua>
      local d = db.open("data/plants.dbl")          -- the app's own folder is the working folder
      page.title = "Plants"
      function post.water(req) d:exec("update plant set watered = 1 where name = ?", req.form.name) end
    </lua>
    <card title="Plants">
      {% for _, p in ipairs(d:query("select * from plant")) do %}
        <p>{{ p.name }} <button post="water" vals={{ {name = p.name} }}>Water</button></p>
      {% end %}
    </card>

  {{ e }} is text, escaped; {{{ e }}} markup as it is; {% lua %} a statement ({% end %} closes a block).
  Kit components are tags; attr={{ e }} passes a table or a boolean; every tag is closed (<x/> or </x>).
  post="water" names the page's action: it runs, the page runs again from its top, and the person's page is
  updated in place. An action may return "#id" (that element alone), { redirect = "?x=1" }, or a value the
  markup reads as result (a form's errors). Links in an app are relative to it ("list", "?note=a").
  A page that does not compile answers with its file, line and why.

  The app as its person sees it, in this computer's browser:
    open app              its page: title, words and controls, each control with an id
    open app/plants       any path of it
    click <id|words>      follows a link, presses a button (hx-post sends, then the page is shown again)
    type <id|words> <text>   fills a field       submit [id|words]   sends a form
    page                  the page's words again  ui   its controls   back   tabs
  """

  @doc "`help page`'s last part: how this computer serves its pages, and how to look at it."
  def help, do: @help

  @types ~w(text/html text/plain text/css text/csv application/json)

  @doc "The request as the app reads it."
  def request(method, path, query, form, headers) do
    %{
      "method" => String.upcase(method),
      "path" => "/" <> String.trim_leading(path, "/"),
      "query" => query,
      "form" => form,
      "headers" => Map.new(headers)
    }
  end

  @doc """
  Asks the computer's app; `{status, headers, body}` ready to send from `origin` (scheme://host:port). `ancestors:`
  who may frame the page (the CSP's frame-ancestors; its own origin unless said, as when an app is served on a
  domain of its own and framed by the site the person signed in to).
  """
  def answer(id, req, origin, base, opts \\ []) do
    {status, headers, body, _err} = Moss.Computer.serve(id, req)
    root = base
    base = app_base(base, headers["x-moss-app"])
    type = content_type(headers)
    # htmx swaps a fragment into a page that has its <base> already
    page_base = if req["headers"]["hx-request"] == "true", do: nil, else: base
    body = if type == "text/html", do: body |> Clean.html() |> with_base(page_base), else: body

    headers =
      headers
      |> Map.drop([
        "content-type",
        "content-security-policy",
        "x-content-type-options",
        "set-cookie"
      ])
      |> Map.take([
        "location",
        "cache-control",
        "hx-redirect",
        "hx-refresh",
        "hx-trigger",
        "hx-push-url"
      ])
      |> Map.update("location", nil, &inside(origin, base, root, &1))
      |> Map.update("hx-redirect", nil, &inside(origin, base, root, &1))
      |> Enum.reject(fn {_, v} -> v == nil end)
      |> Map.new()
      |> Map.merge(%{
        "content-type" => type <> "; charset=utf-8",
        "x-content-type-options" => "nosniff",
        "content-security-policy" => policy(origin, base, Keyword.get(opts, :ancestors, "'self'")),
        "referrer-policy" => "no-referrer"
      })

    {status, headers, body}
  end

  # a page of an app answers from the app's own root: its links, forms and redirects are the app's
  # where a redirect may send the browser: within the computer's app path, or else to the app's own root (the
  # isolation review, 2026-10-04: an app's { redirect = "https://evil/" } sent people off arock.ai from its page)
  defp inside(origin, base, root, to) do
    url = URI.to_string(URI.merge(origin <> base, to))
    if String.starts_with?(url, origin <> root), do: url, else: origin <> base
  rescue
    _ -> origin <> base
  end

  defp app_base(base, nil), do: base

  defp app_base(base, app) do
    if Regex.match?(~r"\A[a-z0-9][a-z0-9-]{0,63}\z", app), do: base <> app <> "/", else: base
  end

  defp content_type(headers) do
    t =
      headers
      |> Map.get("content-type", "text/html")
      |> String.split(";")
      |> hd()
      |> String.trim()

    if t in @types, do: t, else: "text/plain"
  end

  defp policy(origin, base, ancestors) do
    app = origin <> base
    p = Clean.policy()
    scripts = p.scripts |> Enum.sort() |> Enum.map_join(" ", &(origin <> &1))

    Enum.join(
      [
        "default-src 'none'",
        "script-src #{scripts}",
        "style-src 'unsafe-inline' #{origin}#{p.css} #{app}",
        "img-src data: #{app}",
        "connect-src #{app}",
        "form-action #{app}",
        "base-uri #{app}",
        "frame-ancestors #{ancestors}",
        # the page has no origin wherever it is opened, as the desktop's sandboxed frame gives it: opened on its own
        # it never runs as the site that serves it (arock.ai), with that site's cookies
        "sandbox allow-scripts allow-forms"
      ],
      "; "
    )
  end

  defp with_base(html, nil), do: html

  defp with_base(html, base) do
    tag = ~s(<base href="#{base}">)

    case Regex.run(~r/<head[^>]*>/i, html, return: :index) do
      [{at, len}] ->
        binary_part(html, 0, at + len) <>
          tag <> binary_part(html, at + len, byte_size(html) - at - len)

      nil ->
        tag <> html
    end
  end
end

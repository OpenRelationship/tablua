defmodule Moss.Computer.App do
  @moduledoc """
  The computer's app, as a browser gets it: `/home/app.lua` answers each
  request (`Moss.Computer.Script.serve/2`), and its page goes out as HTML the
  person's browser draws, with htmx as its only script.

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

  Apps: a computer has one app, /home/app.lua, that its person opens in their browser.

    return function(req) ... end      (or a table with handle = function(req))
    req = { method = "GET", path = "/plants/fern", query = {k = v}, form = {k = v}, headers = {k = v} }
    answer HTML text (ui.page{...} for a page, ui.render(node) for a fragment htmx swaps in), or
    { status = 404, body = "...", headers = {...} }, or { redirect = "plants" }
  It runs with /home as its working folder. Paths are the app's own: hx-post = "add" reaches path "/add", and
  a request from htmx has headers["hx-request"] == "true". Keep what it shows in a database (db.open), since
  each request is a fresh run.

  The app as its person sees it, in this computer's browser:
    open app              its page: title, words and controls, each control with an id
    open app/plants       any path of it
    click <id|words>      follows a link, presses a button (hx-post sends, then the page is shown again)
    type <id|words> <text>   fills a field       submit [id|words]   sends a form
    page                  the page's words again  ui   its controls   back   tabs
  """

  @doc "`help shroomi`'s last part: how this computer serves an app, and how to look at it."
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

  @doc "Asks the computer's app; `{status, headers, body}` ready to send from `origin` (scheme://host:port)."
  def answer(id, req, origin, base) do
    {status, headers, body, _err} = Moss.Computer.serve(id, req)
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
      |> Map.update("location", nil, &URI.to_string(URI.merge(origin <> base, &1)))
      |> Enum.reject(fn {_, v} -> v == nil end)
      |> Map.new()
      |> Map.merge(%{
        "content-type" => type <> "; charset=utf-8",
        "x-content-type-options" => "nosniff",
        "content-security-policy" => policy(origin, base),
        "referrer-policy" => "no-referrer"
      })

    {status, headers, body}
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

  defp policy(origin, base) do
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
        "frame-ancestors 'self'"
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

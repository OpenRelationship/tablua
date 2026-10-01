defmodule Moss.Computer.App do
  @moduledoc """
  The computer's app, as a browser gets it: `/home/app.lua` answers each
  request (`Moss.Computer.Script.serve/2`), and its page goes out as HTML the
  person's browser draws, with htmx as its only script.

  The page is the agent's writing, so nothing in it runs as code: the one
  script allowed is the pinned htmx file Moss serves, an app answers only in
  types no browser runs as script (sent with `nosniff`), and its requests and
  forms reach no path but the app's own. `base` is where the app lives (for a
  person, `/computers/<id>/app/`); the page gets a `<base>` there, so its
  relative links and hx- paths stay inside it.
  """

  @htmx "/vendor/htmx-2.0.4.min.js"
  @types ~w(text/html text/plain text/css text/csv application/json)

  def htmx, do: @htmx

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
    body = if type == "text/html", do: with_base(body, base), else: body

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

    Enum.join(
      [
        "default-src 'none'",
        "script-src #{origin}#{@htmx}",
        "style-src 'unsafe-inline' #{app}",
        "img-src data: #{app}",
        "connect-src #{app}",
        "form-action #{app}",
        "base-uri #{app}",
        "frame-ancestors 'self'"
      ],
      "; "
    )
  end

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

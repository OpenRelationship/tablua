defmodule MossWeb.SessionController do
  @moduledoc "Signing in to the host's pages with a person's token, and out (`MossWeb.Auth`)."
  use Phoenix.Controller, formats: [:html]
  import Plug.Conn
  alias MossWeb.Auth

  def new(conn, params),
    do: render_form(conn, Auth.back_to(params["to"]), nil)

  def create(conn, %{"token" => token} = params) do
    case Auth.person(token) do
      nil ->
        # a wrong token costs a second, so guessing is slow
        Process.sleep(1_000)

        conn
        |> put_status(401)
        |> render_form(Auth.back_to(params["to"]), "That token does not sign anyone in.")

      name ->
        conn
        |> configure_session(renew: true)
        |> put_session(:person, name)
        |> redirect(to: Auth.back_to(params["to"]))
    end
  end

  def delete(conn, _params),
    do: conn |> configure_session(drop: true) |> redirect(to: "/login")

  defp render_form(conn, to, error) do
    token = Plug.CSRFProtection.get_csrf_token()

    html(conn, """
    <!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
    <title>Sign in · Moss</title><link rel="stylesheet" href="/assets/css/app.css"></head>
    <body class="grid min-h-screen place-items-center bg-slate-50 px-4 text-slate-900">
    <form method="post" action="/login" class="w-full max-w-sm rounded-lg border border-slate-200 bg-white p-6 shadow-sm">
      <h1 class="mb-1 text-lg font-semibold">Moss</h1>
      <p class="mb-4 text-sm text-slate-500">Sign in with your token to see the computers and the post.</p>
      #{if error, do: ~s(<p role="alert" class="mb-3 text-sm text-rose-700">#{error}</p>), else: ""}
      <input type="hidden" name="_csrf_token" value="#{token}">
      <input type="hidden" name="to" value="#{Plug.HTML.html_escape(to)}">
      <label class="mb-1 block text-sm font-medium" for="token">Token</label>
      <input id="token" name="token" type="password" autocomplete="current-password" required autofocus
        class="mb-4 w-full rounded-md border border-slate-300 px-3 py-2 text-sm">
      <button class="w-full rounded-md bg-slate-900 px-3 py-2 text-sm font-medium text-white hover:bg-slate-700">Sign in</button>
    </form></body></html>
    """)
  end
end

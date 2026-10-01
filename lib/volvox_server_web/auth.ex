defmodule VolvoxServerWeb.Auth do
  @moduledoc """
  Who may see the host's pages. They are the node's own: a run's log, an
  agent's computer (where a person may type a command), the post (where a
  person releases held letters and sets routes). A person signs in with a token
  from config `page_tokens` (token => name; in production from
  `VOLVOX_PAGE_TOKENS`, `name:token,...`), and the session keeps the name.

  `require_person/2` guards the routes, `on_mount(:person, ...)` every live
  view (a live socket is checked on its own, not only the page that opened it).
  A name no longer in the config is signed out at its next page.
  """
  import Plug.Conn
  import Phoenix.Controller

  @doc "The person a token signs in, or nil; every token is compared, in constant time."
  def person(token) when is_binary(token) do
    # a pasted token often brings a newline with it
    token = String.trim(token)
    if token == "", do: nil, else: match(token)
  end

  def person(_), do: nil

  defp match(token) do
    Enum.reduce(tokens(), nil, fn {t, name}, found ->
      if Plug.Crypto.secure_compare(t, token), do: name, else: found
    end)
  end

  @doc "Whether a name from a session is still one the config lets in."
  def known?(name) when is_binary(name), do: name in Map.values(tokens())
  def known?(_), do: false

  def require_person(conn, _opts) do
    if known?(get_session(conn, :person)) do
      assign(conn, :person, get_session(conn, :person))
    else
      conn
      |> configure_session(drop: true)
      |> redirect(to: "/login?" <> URI.encode_query(%{"to" => conn.request_path}))
      |> halt()
    end
  end

  def on_mount(:person, _params, session, socket) do
    if known?(session["person"]),
      do: {:cont, Phoenix.Component.assign(socket, :person, session["person"])},
      else: {:halt, Phoenix.LiveView.redirect(socket, to: "/login")}
  end

  @doc "Where to go after signing in: a path on this host, never another site."
  def back_to("/" <> rest = path) do
    if String.starts_with?(rest, ["/", "\\"]), do: "/mail", else: path
  end

  def back_to(_), do: "/mail"

  defp tokens, do: Application.get_env(:volvox_server, :page_tokens, %{})
end

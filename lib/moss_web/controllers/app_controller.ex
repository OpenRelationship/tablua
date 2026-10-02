defmodule MossWeb.AppController do
  @moduledoc """
  A computer's app for its person (`Moss.Computer.App`): `/computers/<id>/app/...`
  is whatever the `.lui` page at that path answers, for the computer's owner only. It takes
  htmx's requests without a CSRF token, as a page with no script of its own
  cannot carry one; the session cookie is SameSite=Lax, so another site's form
  posts arrive without it.
  """
  use MossWeb, :controller

  alias Moss.Computer.App

  def serve(conn, %{"id" => id} = params) do
    path = params["path"] || []

    cond do
      not (Moss.Computer.id?(id) and Moss.Owners.claim(id, conn.assigns.person) == :ok) ->
        send_resp(conn, 404, "There is no computer #{id} of yours.")

      path == [] and not String.ends_with?(conn.request_path, "/") ->
        redirect(conn, to: "/computers/#{id}/app/")

      true ->
        answer(conn, id, path, "/computers/#{id}/app/")
    end
  end

  @doc "Asks computer `id`'s app for `path` and sends its answer, the page's `<base>` at `base`."
  def answer(conn, id, path, base) do
    req =
      App.request(
        conn.method,
        Enum.join(path, "/"),
        conn.query_params,
        form(conn.body_params),
        for(
          {k, v} <- conn.req_headers,
          k == "accept" or String.starts_with?(k, "hx-"),
          do: {k, v}
        )
      )

    origin = "#{conn.scheme}://#{conn.host}#{port(conn)}"
    {status, headers, body} = App.answer(id, req, origin, base)
    conn |> merge_resp_headers(headers) |> send_resp(status, body)
  end

  # flat text fields only: what a form sends
  defp form(params), do: for({k, v} <- params, is_binary(v), into: %{}, do: {k, v})

  defp port(%{scheme: :http, port: 80}), do: ""
  defp port(%{scheme: :https, port: 443}), do: ""
  defp port(conn), do: ":#{conn.port}"
end

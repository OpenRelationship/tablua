defmodule MossWeb.FrameController do
  @moduledoc """
  A computer's app in its window (`MossWeb.Frame`): `/computers/<id>/frame/<cap>/...` answers as the app route
  does (`MossWeb.AppController`: the same cleaning, policy and `nosniff`, the `<base>` at the cap's path), to
  whoever holds the cap. The frame's origin is opaque, so its htmx requests come from `null` and are answered
  with CORS, preflights included. No session is read here: a cookie opens nothing under this path.
  """
  use MossWeb, :controller

  alias MossWeb.Frame

  def serve(conn, %{"id" => id, "cap" => cap} = params) do
    path = params["path"] || []
    base = Frame.base(id, cap)

    cond do
      Frame.check(cap, id) == :error ->
        conn |> merge_resp_headers(Frame.cors()) |> send_resp(403, "This window has closed.")

      conn.method == "OPTIONS" ->
        conn |> merge_resp_headers(Frame.preflight()) |> send_resp(204, "")

      path == [] and not String.ends_with?(conn.request_path, "/") ->
        conn |> merge_resp_headers(Frame.cors()) |> redirect(to: base)

      true ->
        conn
        |> merge_resp_headers(Frame.cors())
        |> MossWeb.AppController.answer(id, path, base)
    end
  end
end

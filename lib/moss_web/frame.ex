defmodule MossWeb.Frame do
  @moduledoc """
  The capability that opens a computer's app in its window (Arock PROJECT.md §16.1, check 6).

  `ComputerLive` draws the app in a sandboxed frame without `allow-same-origin`, so the frame's origin is opaque
  and its requests carry no cookie Moss relies on. Its `src` is `/computers/<id>/frame/<cap>/`: `cap` is a
  `Phoenix.Token` naming the person and the computer, signed with the endpoint's secret for this purpose alone,
  good for an hour. Every request under that path is authorized by the cap and nothing else
  (`MossWeb.FrameController`), and only while the person it names is still let in and still owns the computer.
  The app's `<base>` is that path, so the cap travels with every relative link and htmx request.

  A cap is a token: it is never logged (`MossWeb.Endpoint.log_level/1`, the router's `log: false`).
  """

  @salt "app-frame"
  @max_age 3600

  @doc "A fresh cap for `person` to open computer `id`'s app."
  def cap(person, id), do: Phoenix.Token.sign(MossWeb.Endpoint, @salt, {person, id})

  @doc "The frame's path for `cap`, where the app's `<base>` points."
  def base(id, cap), do: "/computers/#{id}/frame/#{cap}/"

  @doc "`{:ok, person}` when `cap` opens computer `id` now, else `:error`."
  def check(cap, id) do
    with {:ok, {person, ^id}} <-
           Phoenix.Token.verify(MossWeb.Endpoint, @salt, cap, max_age: @max_age),
         true <- MossWeb.Auth.known?(person) and Moss.Owners.mine(id, person) do
      {:ok, person}
    else
      _ -> :error
    end
  end

  # what htmx sends, and what of an answer it reads
  @request_headers ~w(hx-request hx-current-url hx-target hx-trigger hx-trigger-name hx-boosted hx-prompt
                      hx-history-restore-request content-type)
  @response_headers ~w(hx-redirect hx-refresh hx-trigger hx-push-url location)

  @doc """
  CORS for the frame's opaque (`null`) origin. Any origin is allowed and no credentials: the cap in the path is
  the only authority, so `*` grants nothing a page could not already do with the path.
  """
  def cors do
    %{
      "access-control-allow-origin" => "*",
      "access-control-expose-headers" => Enum.join(@response_headers, ", ")
    }
  end

  @doc "The answer to a preflight."
  def preflight do
    Map.merge(cors(), %{
      "access-control-allow-methods" => "GET, POST, PUT, PATCH, DELETE",
      "access-control-allow-headers" => Enum.join(@request_headers, ", "),
      "access-control-max-age" => "600"
    })
  end
end

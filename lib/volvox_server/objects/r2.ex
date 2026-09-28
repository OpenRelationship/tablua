defmodule VolvoxServer.Objects.R2 do
  @moduledoc """
  Objects in the R2 bucket `volvox-runs` through Cloudflare's REST object API
  (`/accounts/<account>/r2/buckets/<bucket>/objects/<key>`): PUT uploads the
  raw body, GET downloads it (404: no such object), DELETE removes it.

  The bearer token is wrangler's OAuth token, from `npx wrangler auth token`
  (its last stdout line; wrangler refreshes it). It is cached in memory,
  fetched again once when a request answers 401, and never logged, printed,
  written to a file or put in an error.
  """
  @behaviour VolvoxServer.Objects

  @account "6d4b74aeb10f455fbf88141901e7595d"
  @bucket "volvox-runs"
  @base "https://api.cloudflare.com/client/v4/accounts/#{@account}/r2/buckets/#{@bucket}/objects/"
  @key {__MODULE__, :token}

  @impl true
  def get(key) do
    case request(:get, key, nil) do
      {:ok, 200, body} -> {:ok, body}
      {:ok, 404, _} -> :not_found
      other -> failure(other)
    end
  end

  @impl true
  def put(key, body) do
    case request(:put, key, body) do
      {:ok, status, _} when status in 200..299 -> :ok
      other -> failure(other)
    end
  end

  @impl true
  def delete(key) do
    case request(:delete, key, nil) do
      {:ok, status, _} when status in 200..299 or status == 404 -> :ok
      other -> failure(other)
    end
  end

  @doc "Whether wrangler hands out a token (so R2 can be used at all)."
  def available?, do: token(:fresh) != nil

  @doc "The request for `key` with `token`, as sent; exposed so tests can check it offline."
  def build(method, key, body, token) do
    Req.new(
      method: method,
      url: @base <> encode(key),
      body: body,
      auth: {:bearer, token},
      headers: [{"content-type", "application/octet-stream"}],
      retry: false,
      decode_body: false,
      receive_timeout: 120_000
    )
  end

  # Each path segment escaped, the slashes kept, as the API names objects.
  defp encode(key) do
    key
    |> String.split("/")
    |> Enum.map_join("/", fn part -> URI.encode(part, &URI.char_unreserved?/1) end)
  end

  defp request(method, key, body, retried \\ false) do
    case token(if retried, do: :fresh, else: :cached) do
      nil ->
        {:error, :no_token}

      token ->
        case Req.request(build(method, key, body, token)) do
          {:ok, %{status: 401}} when not retried -> request(method, key, body, true)
          {:ok, %{status: status, body: resp}} -> {:ok, status, resp}
          {:error, e} -> {:error, Exception.message(e)}
        end
    end
  end

  defp failure({:ok, status, body}),
    do: {:error, {:r2, status, String.slice(to_string(body), 0, 200)}}

  defp failure({:error, reason}), do: {:error, reason}

  defp token(:cached), do: :persistent_term.get(@key, nil) || token(:fresh)

  defp token(:fresh) do
    token = wrangler_token()
    if token, do: :persistent_term.put(@key, token)
    token
  end

  defp wrangler_token do
    case System.cmd("npx", ["wrangler", "auth", "token"], stderr_to_stdout: false) do
      {out, 0} ->
        last =
          out |> String.split("\n", trim: true) |> List.last() |> Kernel.||("") |> String.trim()

        if last =~ ~r/^[A-Za-z0-9._~+\/=-]{20,}$/, do: last

      _ ->
        nil
    end
  rescue
    ErlangError -> nil
  end
end

defmodule Moss.Fetch do
  @moduledoc """
  The fetch port over Req: `{ method, url, headers, body, timeout }` (as
  decoded from Lua) to `{:ok, status, body}`, or `{:error, message}` for a
  transport failure. No retries here: `ports.call` owns the retry policy. The
  request, and so the key in its headers, is never logged or put in an error.
  """

  def request(req) do
    opts =
      [
        method: req |> Map.get("method", "GET") |> String.downcase() |> String.to_existing_atom(),
        url: Map.fetch!(req, "url"),
        headers: Map.get(req, "headers", []),
        body: Map.get(req, "body"),
        receive_timeout: round(Map.get(req, "timeout", 30) * 1000),
        retry: false,
        decode_body: false
      ] ++ Application.get_env(:moss, :req_options, [])

    case Req.request(opts) do
      {:ok, %Req.Response{status: status, body: body}} -> {:ok, status, body}
      {:error, e} -> {:error, "fetch: " <> Exception.message(e)}
    end
  end
end

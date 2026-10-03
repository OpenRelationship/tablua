defmodule Moss.Fetch do
  @moduledoc """
  The fetch port over Req: `{ method, url, headers, body, timeout }` (as
  decoded from Lua) to `{:ok, status, body}`, or `{:error, message}` for a
  transport failure. No retries here: `ports.call` owns the retry policy. The
  request, and so the key in its headers, is never logged or put in an error.

  Each request runs in a task of its own: a reply that comes after its request gave up (Finch's
  `{:status, ref, 200}`) then dies with the task, instead of waiting in a long-lived caller's mailbox (the
  computer's agent runs a whole build in one process) to break the next request.
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

    # whatever the request raises stays in its task: a 504 that Finch could not match crashed the linked task and
    # with it a whole agent run
    task =
      Task.async(fn ->
        try do
          Req.request(opts)
        rescue
          e -> {:error, e}
        catch
          kind, why -> {:error, RuntimeError.exception(Exception.format_banner(kind, why))}
        end
      end)

    case Task.yield(task, opts[:receive_timeout] + 5_000) || Task.shutdown(task, :brutal_kill) do
      {:ok, {:ok, %Req.Response{status: status, body: body}}} -> {:ok, status, body}
      {:ok, {:error, e}} -> {:error, "fetch: " <> Exception.message(e)}
      {:exit, why} -> {:error, "fetch: " <> Exception.format_exit(why)}
      nil -> {:error, "fetch: no answer in time"}
    end
  end
end

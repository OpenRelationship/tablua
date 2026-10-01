defmodule Moss.Computer.Http do
  @moduledoc """
  The web for the computer's programs: the `moss` module's imports that
  `fetch` in `js` calls (Arock's `scripts/build/computer/fetch.c`). A request
  goes out through `Computer.Net`, under the computer's web rules (public
  addresses only, every redirect checked again, #{15} s), never a socket of
  the program's own.

    * `http_request(ptr, len) -> n`: reads the request (u32 meta length, meta
      JSON `{method, url, headers, kind}`, body), fetches it, and keeps the
      answer (u32 meta length, meta JSON `{status, statusText, url,
      redirected, headers}`, body): n is its size, or minus the size of the
      reason it failed.
    * `http_take(ptr)`: copies the kept answer out.

  Like the open files, the kept answer lives in the instance's own process.
  """
  alias Moss.Computer.{Net, Wasi}

  @methods ~w(GET HEAD POST PUT PATCH DELETE OPTIONS)
  @limit 32 * 1024 * 1024
  @types %{
    "text" => "text/plain;charset=UTF-8",
    "form" => "application/x-www-form-urlencoded;charset=UTF-8"
  }

  def call("http_request", _c), do: fn ctx, [ptr, len] -> request(Wasi.read(ctx, ptr, len)) end

  def call("http_take", _c) do
    fn ctx, [ptr] ->
      Wasi.write(ctx, ptr, Process.delete(__MODULE__) || "")
      nil
    end
  end

  # an import this host does not answer fails the way a missing network would
  def call(_name, _c), do: fn _ctx, _args -> -1 end

  defp request(<<n::little-32, meta::binary-size(n), body::binary>>) do
    with {:ok, %{"url" => url} = m} <- Jason.decode(meta),
         method = String.upcase(m["method"] || "GET"),
         true <- method in @methods || {:error, "#{method} is not a method this computer sends"},
         {:ok, resp} <-
           Net.get(url, method: method, headers: headers(m), body: body?(method, body)),
         true <- byte_size(resp.body) <= @limit || {:error, "the answer is over 32 MB"} do
      keep(
        Jason.encode!(%{
          status: resp.status,
          statusText: Plug.Conn.Status.reason_phrase(resp.status),
          url: resp.url,
          redirected: resp.url != url,
          headers: for({k, vs} <- resp.headers, v <- List.wrap(vs), do: [k, v])
        }),
        resp.body
      )
    else
      {:error, %Jason.DecodeError{}} -> fail("the request was not readable")
      {:error, why} -> fail(to_string(why))
      _ -> fail("the request was not readable")
    end
  rescue
    ArgumentError -> fail("#{inspect(@methods)} only")
  end

  defp request(_), do: fail("the request was not readable")

  defp headers(m) do
    given =
      for [k, v] <- m["headers"] || [], is_binary(k) and is_binary(v), do: {String.downcase(k), v}

    type = @types[m["kind"]]

    if type && not List.keymember?(given, "content-type", 0),
      do: [{"content-type", type} | given],
      else: given
  end

  defp body?(method, _) when method in ["GET", "HEAD"], do: nil
  defp body?(_, body), do: body

  defp keep(meta, body) do
    answer = <<byte_size(meta)::little-32, meta::binary, body::binary>>
    Process.put(__MODULE__, answer)
    byte_size(answer)
  end

  defp fail(why) do
    Process.put(__MODULE__, why)
    -byte_size(why)
  end
end

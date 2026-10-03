defmodule MossBrowser.Fetch do
  @moduledoc """
  The way to the web: only http and https to public addresses. A name that resolves to this machine, a private or
  link-local network (the cloud's metadata service among them) is refused, and every redirect is checked again
  before it is followed. A name is resolved once, and the request goes to the address that was checked (the name
  kept for TLS and the Host header), so a name that answers differently the second time cannot reach this machine.

  `get(url, opts)`: `{:ok, %{status, headers, body, url, cut, cookies}}` (the address it ended at) or
  `{:error, why}`. Options:

    * `:method`, `:headers`, `:body`, `:timeout` (ms, 15 s);
    * `:browser`: send what a browser sends (accept, language, gzip) and inflate the answer;
    * `:cookies`: a `MossBrowser.Cookies` jar, sent where it applies and kept up to date through redirects;
    * `:max` (bytes, 32 MB) and `:cut` (read to the cap and say so, instead of refusing);
    * `:allow`: a function of each address that answers `:ok` or `{:error, why}`;
    * `:agent`: the user-agent (`agent/0` when not given);
    * `:resolver`: a function of a host name to its addresses, standing in for DNS;
    * `:req_options`: given to Req last (a test's plug).
  """
  alias MossBrowser.Cookies
  alias MossBrowser.Fetch.Body

  @methods %{
    "GET" => :get,
    "POST" => :post,
    "PUT" => :put,
    "PATCH" => :patch,
    "DELETE" => :delete,
    "HEAD" => :head,
    "OPTIONS" => :options
  }
  @max_bytes 32 * 1024 * 1024
  @hops 5
  # who the browser says it is: an agent, honestly (owner, 2026-10-02)
  @agent "Arock/1.0 (an AI agent browsing for a person; +https://arock.ai/agent)"

  @doc "The methods a request may use."
  def methods, do: Map.keys(@methods)

  @doc "The user-agent a request carries when `:agent` is not given."
  def agent, do: @agent

  @doc "The size cap when `:max` is not given."
  def max_bytes, do: @max_bytes

  def get(url, opts \\ []) do
    case request(url, opts) do
      {:error, :method} -> {:error, "no such method: #{opts[:method]}"}
      {:error, {:too_big, max}} -> {:error, "the answer is over #{max} bytes"}
      other -> other
    end
  end

  @doc "`get/2` with its refusals as terms: `{:error, :method}` and `{:error, {:too_big, max}}`."
  def request(url, opts \\ []), do: hop(url, opts, @hops)

  # what a browser sends that curl does not
  @browser [
    {"accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"},
    {"accept-language", "en-US,en;q=0.9"},
    {"accept-encoding", "gzip, deflate"}
  ]

  defp hop(_url, _opts, 0), do: {:error, "too many redirects"}

  defp hop(url, opts, left) do
    method = Map.get(@methods, String.upcase(Keyword.get(opts, :method, "GET")))
    max = Keyword.get(opts, :max) || @max_bytes
    browser = Keyword.get(opts, :browser, false)
    jar = Keyword.get(opts, :cookies)

    with {:ok, method} <- if(method, do: {:ok, method}, else: {:error, :method}),
         :ok <- Keyword.get(opts, :allow, fn _ -> :ok end).(url),
         {:ok, uri, ip} <- resolve(url, opts),
         cookie = jar && Cookies.header(jar, uri, System.os_time(:second)),
         {:ok, resp} <-
           Req.request(
             [
               method: method,
               url: URI.to_string(%{uri | host: ip_host(ip)}),
               headers:
                 [{"host", host_header(uri)}, {"user-agent", Keyword.get(opts, :agent) || @agent}] ++
                   if(browser, do: @browser, else: []) ++
                   if(cookie, do: [{"cookie", cookie}], else: []) ++
                   Keyword.get(opts, :headers, []),
               connect_options: [hostname: uri.host],
               body: Keyword.get(opts, :body),
               redirect: false,
               retry: false,
               compressed: false,
               raw: true,
               into: Body.into(max, cut: Keyword.get(opts, :cut, false), inflate: browser),
               receive_timeout: Keyword.get(opts, :timeout, 15_000)
             ] ++ Keyword.get(opts, :req_options, [])
           ),
         {:ok, body, cut} <- Body.finish(resp) do
      jar =
        jar &&
          Cookies.put(
            jar,
            uri,
            Req.Response.get_header(resp, "set-cookie"),
            System.os_time(:second)
          )

      opts = if jar, do: Keyword.put(opts, :cookies, jar), else: opts

      case {resp.status, Req.Response.get_header(resp, "location")} do
        {s, [to | _]} when s in [301, 302, 303, 307, 308] ->
          next = uri |> URI.merge(to) |> URI.to_string()

          opts =
            if s == 303 or (s in [301, 302] and Keyword.get(opts, :method) == "POST"),
              do: Keyword.merge(opts, method: "GET", body: nil),
              else: opts

          hop(next, opts, left - 1)

        _ ->
          {:ok,
           %{
             status: resp.status,
             headers: resp.headers,
             body: body,
             url: URI.to_string(uri),
             cut: cut,
             cookies: jar
           }}
      end
    else
      {:error, %{__exception__: true} = e} -> {:error, Exception.message(e)}
      {:error, why} -> {:error, why}
    end
  end

  defp ip_host({_, _, _, _} = ip), do: ip |> :inet.ntoa() |> to_string()
  defp ip_host(ip), do: "[" <> to_string(:inet.ntoa(ip)) <> "]"

  defp host_header(%URI{host: h, port: p, scheme: s}) do
    if {s, p} in [{"http", 80}, {"https", 443}], do: h, else: "#{h}:#{p}"
  end

  @doc "The address, if it is http or https to a public host (`:resolver` as for `get/2`)."
  def public(url, opts \\ []) do
    with {:ok, uri, _ip} <- resolve(url, opts), do: {:ok, uri}
  end

  # The url and the one address its host resolved to, if every address it has is public.
  defp resolve(url, opts) do
    uri = URI.parse(url)
    uri = if uri.scheme == nil, do: URI.parse("https://" <> url), else: uri

    cond do
      uri.scheme not in ["http", "https"] ->
        {:error, "only http and https"}

      uri.host in [nil, ""] ->
        {:error, "no host in #{url}"}

      true ->
        ips = addresses(uri.host, Keyword.get(opts, :resolver))

        if Enum.all?(ips, &public_ip?/1),
          do: {:ok, uri, hd(ips)},
          else: {:error, "#{uri.host} is not on the public internet"}
    end
  end

  defp addresses(host, resolver) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, ip} -> [ip]
      _ -> if resolver, do: resolver.(host), else: dns(host)
    end
  end

  defp dns(host) do
    found =
      for family <- [:inet, :inet6],
          {:ok, ips} <- [:inet.getaddrs(String.to_charlist(host), family)],
          ip <- ips,
          do: ip

    # a name that does not resolve is not public either
    if found == [], do: [{127, 0, 0, 1}], else: found
  end

  defp public_ip?({a, b, _, _}) do
    not (a in [0, 10, 127] or a >= 224 or (a == 169 and b == 254) or (a == 172 and b in 16..31) or
           (a == 192 and b == 168) or (a == 100 and b in 64..127) or (a == 198 and b in 18..19))
  end

  defp public_ip?({0, 0, 0, 0, 0, 0xFFFF, hi, lo}),
    do: public_ip?({div(hi, 256), rem(hi, 256), div(lo, 256), rem(lo, 256)})

  defp public_ip?({a, _, _, _, _, _, _, _} = ip) do
    import Bitwise

    not (ip in [{0, 0, 0, 0, 0, 0, 0, 0}, {0, 0, 0, 0, 0, 0, 0, 1}] or (a &&& 0xFE00) == 0xFC00 or
           (a &&& 0xFFC0) == 0xFE80 or (a &&& 0xFF00) == 0xFF00)
  end
end

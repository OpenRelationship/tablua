defmodule Moss.Computer.Net do
  @moduledoc """
  The computer's way to the web: `curl` (and `wget`, which saves to a file).
  Only http and https to public addresses: a name that resolves to this
  machine, a private or link-local network (the cloud's metadata service among
  them) is refused, and every redirect is checked again before it is followed.
  A name is resolved once, and the request goes to the address that was
  checked (the name kept for TLS and the Host header), so a name that answers
  differently the second time cannot reach this machine. An answer stops at
  #{div(32 * 1024 * 1024, 1_048_576)} MB (config `net_max_bytes`); the methods are #{Enum.join(~w(GET POST PUT PATCH DELETE HEAD OPTIONS), ", ")}.

  `get(url, opts)` is what the browser fetches with: `{:ok, %{status, headers,
  body, url}}` (the address it ended at) or `{:error, why}`.
  """
  alias Moss.Computer.{Cookies, Disk}
  alias Moss.Computer.Net.Body

  @names ~w(curl wget)
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
  @agent "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

  def names, do: @names

  def run(name, args, stdin, state) do
    case parse(args, %{method: nil, headers: [], data: nil, out: nil, include: false, url: nil}) do
      {:ok, %{url: nil}} ->
        {2, "", "#{name}: needs an address\n", state}

      {:ok, o} ->
        o =
          if name == "wget" and o.out == nil,
            do: %{
              o
              | out:
                  o.url
                  |> URI.parse()
                  |> Map.get(:path)
                  |> to_string()
                  |> Path.basename()
                  |> then(&if(&1 in ["", "/"], do: "index.html", else: &1))
            },
            else: o

        body = if o.data == "@-", do: stdin, else: o.data
        method = o.method || if(body, do: "POST", else: "GET")

        case if Map.has_key?(@methods, method),
               do: hop(o.url, [method: method, headers: o.headers, body: body], @hops),
               else: {:error, :method} do
          {:ok, r} ->
            head =
              if o.include,
                do:
                  "HTTP #{r.status}\n" <>
                    Enum.map_join(r.headers, fn {k, v} ->
                      "#{k}: #{Enum.join(List.wrap(v), ", ")}\n"
                    end) <> "\n",
                else: ""

            code = if r.status >= 400, do: 22, else: 0

            if o.out do
              path = Disk.norm(o.out, state.cwd)

              case Disk.write(state.disk, path, r.body) do
                :ok -> {code, head, "", state}
                {:error, e} -> {23, head, "#{name}: #{path}: #{e}\n", state}
              end
            else
              {code, head <> r.body, "", state}
            end

          {:error, :method} ->
            {2, "", "#{name}: no such method: #{method}\n", state}

          {:error, {:too_big, max}} ->
            {63, "", "#{name}: the answer is over #{max} bytes\n", state}

          {:error, why} ->
            {6, "", "#{name}: #{why}\n", state}
        end

      {:error, why} ->
        {2, "", "#{name}: #{why}\n", state}
    end
  end

  def get(url, opts \\ []) do
    case hop(url, opts, @hops) do
      {:error, :method} -> {:error, "no such method: #{opts[:method]}"}
      {:error, {:too_big, max}} -> {:error, "the answer is over #{max} bytes"}
      other -> other
    end
  end

  # what the browser sends that curl does not (Arock feature browser)
  @browser [
    {"accept", "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"},
    {"accept-language", "en-US,en;q=0.9"},
    {"accept-encoding", "gzip, deflate"}
  ]

  defp hop(_url, _opts, 0), do: {:error, "too many redirects"}

  defp hop(url, opts, left) do
    method = Map.get(@methods, String.upcase(Keyword.get(opts, :method, "GET")))
    max = Keyword.get(opts, :max) || Application.get_env(:moss, :net_max_bytes, @max_bytes)
    browser = Keyword.get(opts, :browser, false)
    jar = Keyword.get(opts, :cookies)

    with {:ok, method} <- if(method, do: {:ok, method}, else: {:error, :method}),
         {:ok, uri, ip} <- checked(url),
         cookie = jar && Cookies.header(jar, uri, System.os_time(:second)),
         {:ok, resp} <-
           Req.request(
             [
               method: method,
               url: URI.to_string(%{uri | host: ip_host(ip)}),
               headers:
                 [{"host", host_header(uri)}, {"user-agent", @agent}] ++
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
             ] ++ Application.get_env(:moss, :computer_req_options, [])
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

  # The address to connect to: the url's, public, from one resolution.
  defp checked(url), do: resolve(url)

  @doc "The address, if it is http or https to a public host."
  def public(url) do
    with {:ok, uri, _ip} <- resolve(url), do: {:ok, uri}
  end

  # The url and the one address its host resolved to, if every address it has is public.
  defp resolve(url) do
    uri = URI.parse(url)
    uri = if uri.scheme == nil, do: URI.parse("https://" <> url), else: uri

    cond do
      uri.scheme not in ["http", "https"] ->
        {:error, "only http and https"}

      uri.host in [nil, ""] ->
        {:error, "no host in #{url}"}

      true ->
        ips = addresses(uri.host)

        if Enum.all?(ips, &public_ip?/1),
          do: {:ok, uri, hd(ips)},
          else: {:error, "#{uri.host} is not on the public internet"}
    end
  end

  defp addresses(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, ip} ->
        [ip]

      _ ->
        lookup(host)
    end
  end

  # every address a name has (config `resolver`, a function of the name, stands in for DNS in tests)
  defp lookup(host) do
    case Application.get_env(:moss, :resolver) do
      nil -> dns(host)
      f -> f.(host)
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

  defp parse([], o), do: {:ok, o}
  defp parse(["-X", m | rest], o), do: parse(rest, %{o | method: String.upcase(m)})

  defp parse(["-H", h | rest], o),
    do:
      with(
        [k, v] <- String.split(h, ":", parts: 2),
        do: parse(rest, %{o | headers: o.headers ++ [{String.trim(k), String.trim(v)}]}),
        else: (_ -> {:error, "a header is name: value"})
      )

  defp parse([d, data | rest], o) when d in ["-d", "--data", "--data-raw"],
    do: parse(rest, %{o | data: data})

  defp parse([out, file | rest], o) when out in ["-o", "--output"],
    do: parse(rest, %{o | out: file})

  defp parse(["-i" | rest], o), do: parse(rest, %{o | include: true})
  defp parse(["-" <> _ | rest], o), do: parse(rest, o)
  defp parse([url | rest], o), do: parse(rest, %{o | url: url})
end

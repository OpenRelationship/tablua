defmodule VolvoxServer.Computer.Net do
  @moduledoc """
  The computer's way to the web: `curl` (and `wget`, which saves to a file).
  Only http and https to public addresses: a name that resolves to this
  machine, a private or link-local network (the cloud's metadata service among
  them) is refused, and every redirect is checked again before it is followed.

  `get(url, opts)` is what the browser fetches with: `{:ok, %{status, headers,
  body, url}}` (the address it ended at) or `{:error, why}`.
  """
  alias VolvoxServer.Computer.Disk

  @names ~w(curl wget)
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

        case get(o.url, method: method, headers: o.headers, body: body) do
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

          {:error, why} ->
            {6, "", "#{name}: #{why}\n", state}
        end

      {:error, why} ->
        {2, "", "#{name}: #{why}\n", state}
    end
  end

  def get(url, opts \\ []), do: hop(url, opts, @hops)

  defp hop(_url, _opts, 0), do: {:error, "too many redirects"}

  defp hop(url, opts, left) do
    with {:ok, uri} <- public(url),
         {:ok, resp} <-
           Req.request(
             [
               method:
                 opts
                 |> Keyword.get(:method, "GET")
                 |> String.downcase()
                 |> String.to_existing_atom(),
               url: URI.to_string(uri),
               headers: [{"user-agent", @agent} | Keyword.get(opts, :headers, [])],
               body: Keyword.get(opts, :body),
               redirect: false,
               retry: false,
               decode_body: false,
               receive_timeout: Keyword.get(opts, :timeout, 15_000)
             ] ++ Application.get_env(:volvox_server, :computer_req_options, [])
           ) do
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
           %{status: resp.status, headers: resp.headers, body: resp.body, url: URI.to_string(uri)}}
      end
    else
      {:error, %{__exception__: true} = e} -> {:error, Exception.message(e)}
      {:error, why} -> {:error, why}
    end
  end

  @doc "The address, if it is http or https to a public host."
  def public(url) do
    uri = URI.parse(url)
    uri = if uri.scheme == nil, do: URI.parse("https://" <> url), else: uri

    cond do
      uri.scheme not in ["http", "https"] ->
        {:error, "only http and https"}

      uri.host in [nil, ""] ->
        {:error, "no host in #{url}"}

      true ->
        if Enum.all?(addresses(uri.host), &public_ip?/1),
          do: {:ok, uri},
          else: {:error, "#{uri.host} is not on the public internet"}
    end
  end

  defp addresses(host) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, ip} ->
        [ip]

      _ ->
        v4 =
          case :inet.getaddrs(String.to_charlist(host), :inet),
            do: (
              {:ok, l} -> l
              _ -> []
            )

        v6 =
          case :inet.getaddrs(String.to_charlist(host), :inet6),
            do: (
              {:ok, l} -> l
              _ -> []
            )

        # a name that does not resolve is not public either
        if v4 ++ v6 == [], do: [{127, 0, 0, 1}], else: v4 ++ v6
    end
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

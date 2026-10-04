defmodule Moss.Computer.Net do
  @moduledoc """
  The computer's way to the web: `curl` (and `wget`, which saves to a file), over moss-browser's fetch
  (`MossBrowser.Fetch`: http and https to public addresses only, every redirect checked again, the checked address
  dialled). It reads anywhere public, and sends (a body, or a method other than GET and HEAD) only to a host a tool
  of this computer asks for in NET and the person granted. An answer stops at #{div(32 * 1024 * 1024, 1_048_576)} MB (config `net_max_bytes`); the methods are
  #{Enum.join(~w(GET POST PUT PATCH DELETE HEAD OPTIONS), ", ")}.

  `get(url, opts)` is what the browser fetches with: moss-browser's, with this node's settings (config
  `net_max_bytes`, `user_agent`, `resolver`, `computer_req_options`) given as options.
  """
  alias Moss.Computer.Disk

  @names ~w(curl wget)
  @methods ~w(GET POST PUT PATCH DELETE HEAD OPTIONS)
  @max_bytes 32 * 1024 * 1024

  def names, do: @names

  # Reading reaches any public address, as the browser does; sending (a body, or any other method) only reaches a
  # host a tool of this computer asks for and the person granted, as a tool's own http does: what the person keeps
  # here leaves only where they said it may (the isolation review, 2026-10-04)
  defp sends?(method, body), do: body != nil or method not in ~w(GET HEAD)

  defp granted?(state, url) do
    host = host(url)
    Enum.any?(Moss.Computer.Manifest.grants(state.disk), &match?({_, "NET", ^host}, &1))
  end

  defp host(url), do: URI.parse(url).host || url

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

        fetched =
          cond do
            method not in @methods ->
              {:error, :method}

            not sends?(method, body) or granted?(state, o.url) ->
              MossBrowser.Fetch.request(o.url, opts(method: method, headers: o.headers, body: body))

            true ->
              {:error, {:not_granted, host(o.url)}}
          end

        case fetched do
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

          {:error, {:not_granted, host}} ->
            {2, "",
             "#{name}: sending to #{host} needs a tool in manifest.org with NET #{host} that the person granted " <>
               "(reading, GET or HEAD, reaches any public address)\n", state}

          {:error, {:too_big, max}} ->
            {63, "", "#{name}: the answer is over #{max} bytes\n", state}

          {:error, why} ->
            {6, "", "#{name}: #{why}\n", state}
        end

      {:error, why} ->
        {2, "", "#{name}: #{why}\n", state}
    end
  end

  def get(url, opts \\ []), do: MossBrowser.Fetch.get(url, opts(opts))

  @doc "The address, if it is http or https to a public host."
  def public(url), do: MossBrowser.Fetch.public(url, opts([]))

  @doc "The user-agent every request carries: Arock's, or config `user_agent`."
  def agent, do: Application.get_env(:moss, :user_agent, MossBrowser.Fetch.agent())

  # this node's settings, under what the caller gave
  defp opts(given) do
    [
      max: Application.get_env(:moss, :net_max_bytes, @max_bytes),
      agent: agent(),
      resolver: Application.get_env(:moss, :resolver),
      req_options: Application.get_env(:moss, :computer_req_options, [])
    ]
    |> Keyword.merge(Enum.reject(given, fn {_, v} -> v == nil end))
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

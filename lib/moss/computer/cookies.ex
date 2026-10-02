defmodule Moss.Computer.Cookies do
  @moduledoc """
  The browser's cookie jar, one per computer, kept in its session (curl keeps none). `put/4` takes an answer's
  `Set-Cookie` values for the address that sent them; `header/3` is the `Cookie` an address gets: a cookie goes
  only to its domain (only its host when it named none), under its path, over https when it is secure, and
  until it expires (`Max-Age` before `Expires`). Times are Unix seconds, given, so the jar is the same for any
  clock.

  A `Domain` must be the host or a parent of it, hold a dot, not be an address, and not be a public suffix this
  jar knows (`co.uk`, `github.io` and the like: a short list, not the whole Public Suffix List), so one site
  cannot set a cookie for all of them. SameSite is not enforced: every request here is the agent's own. A jar
  holds 50 cookies a domain and 1,000 in all, each name and value 4 KB at most.
  """

  @suffixes ~w(co.uk org.uk ac.uk gov.uk ltd.uk plc.uk com.au net.au org.au edu.au gov.au co.nz org.nz co.jp
               ne.jp or.jp co.kr com.br com.cn com.mx com.tr com.sg co.in co.za github.io gitlab.io pages.dev
               workers.dev vercel.app netlify.app herokuapp.com fly.dev appspot.com blogspot.com cloudfront.net
               azurewebsites.net s3.amazonaws.com firebaseapp.com web.app)
  @per_domain 50
  @all 1_000

  def new, do: %{}

  def put(jar, %URI{} = uri, values, now) do
    Enum.reduce(values, jar, fn v, jar ->
      case parse(v, uri, now) do
        {:ok, c} -> store(jar, c, now)
        :error -> jar
      end
    end)
  end

  def header(jar, %URI{} = uri, now) do
    host = String.downcase(uri.host || "")
    path = if uri.path in [nil, ""], do: "/", else: uri.path

    jar
    |> Map.values()
    |> Enum.filter(fn c ->
      live?(c, now) and (not c.secure or uri.scheme == "https") and domain?(c, host) and
        path?(c.path, path)
    end)
    |> Enum.sort_by(&(-byte_size(&1.path)))
    |> case do
      [] -> nil
      cs -> Enum.map_join(cs, "; ", &"#{&1.name}=#{&1.value}")
    end
  end

  @doc "The sites and their cookies' names, never their values."
  def list(jar, now) do
    jar
    |> Map.values()
    |> Enum.filter(&live?(&1, now))
    |> Enum.group_by(& &1.domain, & &1.name)
    |> Enum.sort()
  end

  @doc "The jar without the cookies of a site (and its subdomains), or empty."
  def clear(_jar, nil), do: %{}

  def clear(jar, site) do
    site = String.downcase(site)
    Map.reject(jar, fn {_, c} -> c.domain == site or String.ends_with?(c.domain, "." <> site) end)
  end

  # -- reading Set-Cookie ------------------------------------------------------------------------

  defp parse(value, uri, now) do
    [pair | attrs] = String.split(value, ";")
    host = String.downcase(uri.host || "")

    with [name, val] <- String.split(pair, "=", parts: 2),
         name = String.trim(name),
         true <- name != "" and byte_size(name) + byte_size(val) <= 4096,
         attrs = Map.new(attrs, &attribute/1),
         {:ok, domain, host_only} <- domain(attrs["domain"], host) do
      {:ok,
       %{
         name: name,
         value: String.trim(val),
         domain: domain,
         host_only: host_only,
         path: path(attrs["path"], uri.path),
         secure: Map.has_key?(attrs, "secure"),
         expires: expires(attrs, now)
       }}
    else
      _ -> :error
    end
  end

  defp attribute(a) do
    case String.split(a, "=", parts: 2) do
      [k, v] -> {k |> String.trim() |> String.downcase(), String.trim(v)}
      [k] -> {k |> String.trim() |> String.downcase(), ""}
    end
  end

  defp domain(nil, host), do: {:ok, host, true}
  defp domain("", host), do: {:ok, host, true}

  defp domain(d, host) do
    d = d |> String.trim_leading(".") |> String.downcase()

    ok =
      String.contains?(d, ".") and not ip?(d) and d not in @suffixes and
        (host == d or String.ends_with?(host, "." <> d))

    if ok, do: {:ok, d, false}, else: :error
  end

  defp ip?(d), do: match?({:ok, _}, :inet.parse_address(String.to_charlist(d)))

  defp path("/" <> _ = p, _), do: p

  defp path(_, req) do
    case req do
      "/" <> rest ->
        if String.contains?(rest, "/"),
          do: "/" <> (rest |> String.split("/") |> Enum.drop(-1) |> Enum.join("/")),
          else: "/"

      _ ->
        "/"
    end
  end

  defp expires(%{"max-age" => age}, now) do
    case Integer.parse(age) do
      {n, _} -> now + n
      :error -> nil
    end
  end

  defp expires(%{"expires" => date}, _now), do: http_date(date)
  defp expires(_, _), do: nil

  @months ~w(jan feb mar apr may jun jul aug sep oct nov dec)
  defp http_date(s) do
    with [_, d, m, y, hh, mm, ss] <-
           Regex.run(~r/(\d{1,2})[ -]([a-z]{3})[a-z]*[ -](\d{2,4}) (\d{1,2}):(\d{2}):(\d{2})/i, s),
         m when m != nil <- Enum.find_index(@months, &(&1 == String.downcase(m))),
         y = String.to_integer(y),
         y = if(y < 100, do: y + if(y < 70, do: 2000, else: 1900), else: y),
         {:ok, dt} <-
           NaiveDateTime.new(
             y,
             m + 1,
             String.to_integer(d),
             String.to_integer(hh),
             String.to_integer(mm),
             String.to_integer(ss)
           ) do
      dt |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()
    else
      _ -> nil
    end
  end

  # -- the jar -----------------------------------------------------------------------------------

  defp store(jar, c, now) do
    key = {c.domain, c.path, c.name}

    cond do
      not live?(c, now) -> Map.delete(jar, key)
      Map.has_key?(jar, key) -> Map.put(jar, key, c)
      Enum.count(jar, fn {{d, _, _}, _} -> d == c.domain end) >= @per_domain -> jar
      map_size(jar) >= @all -> jar
      true -> Map.put(jar, key, c)
    end
  end

  defp live?(%{expires: nil}, _now), do: true
  defp live?(%{expires: e}, now), do: e > now

  defp domain?(%{host_only: true, domain: d}, host), do: host == d
  defp domain?(%{domain: d}, host), do: host == d or String.ends_with?(host, "." <> d)

  defp path?(cp, p),
    do:
      p == cp or
        (String.starts_with?(p, cp) and
           (String.ends_with?(cp, "/") or String.at(p, byte_size(cp)) == "/"))
end

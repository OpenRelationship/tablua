defmodule Moss.Computer.Script.Http do
  @moduledoc """
  Lua's `http` on the computer (`http.request{ method, url, headers, body } -> { status, body, url, headers }`),
  under the web rules (`Moss.Computer.Net`) and the run's reach (Arock's feature `manifest`): a run of a tool
  reaches the hosts its NET asks for and the person granted, each redirect checked again; any other run reaches
  nothing beyond its computer.
  """
  alias Moss.Computer.Net

  @doc "Binds `http` into the run's Lua for a run of `state`."
  def bind(lua, state) do
    Lua.set!(lua, [:__sys, :http], fn [{:tref, _} = t | _], lua ->
      req = Map.new(Lua.decode!(lua, t))
      headers = for {k, v} <- Map.new(req["headers"] || []), do: {to_string(k), to_string(v)}
      method = String.upcase(req["method"] || "GET")
      url = req["url"] || ""

      with true <- method in ~w(GET POST PUT PATCH DELETE HEAD) || {:error, "no such method: #{method}"},
           allow = &reach(state[:reach], &1),
           {:ok, r} <- Net.get(url, method: method, headers: headers, body: req["body"], allow: allow) do
        hs = for {k, v} <- r.headers, do: {k, Enum.join(List.wrap(v), ", ")}
        page = %{"status" => r.status, "body" => r.body, "url" => r.url, "headers" => Map.new(hs)}
        {t, lua} = Lua.encode!(lua, page)
        {[t], lua}
      else
        {:error, why} -> {[nil, to_string(why)], lua}
      end
    end)
  end

  @doc "`:ok` when a run with `reach` may fetch `url`, or `{:error, why}` naming what to ask for."
  def reach(nil, _url),
    do:
      {:error,
       "a lua run outside a tool reaches nothing beyond its computer: make the code a tool in manifest.org " <>
         "with NET <host>, and the person grants it"}

  def reach(%{tool: tool, asked: asked, granted: granted}, url) do
    host = URI.parse(url).host || url

    cond do
      {"NET", host} in granted -> :ok
      {"NET", host} in asked -> {:error, "NET #{host}: #{tool} asks for it, and the person has not said yes yet"}
      true -> {:error, "NET #{host}: #{tool} does not ask for it (add it to the tool's NET; the person grants it)"}
    end
  end
end

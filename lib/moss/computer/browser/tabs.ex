defmodule Moss.Computer.Browser.Tabs do
  @moduledoc """
  The browser's tabs, bounded (Arock feature browser): eight tabs at most, the oldest closed with a word when a
  ninth opens; twenty pages back in each, kept as addresses (a page a form answered keeps its words, `Page.slim`,
  since fetching its address again would not give it back). A tab is

      %{url: "https://…", page: %Page{} | nil, history: [%{url, page}], ui_at: nil, values: %{}}

  `kept/1` is what the computer's file keeps: each tab's address and typed values, its history's addresses, the
  cookie jar and the app's screen; never a page but a form's answer. `restore/1` reads it back with every page
  unloaded; a tab's page is fetched again the first time it is used (`Browser.Nav.load/2`), its typed values put
  back.
  """
  alias MossBrowser.{Cookies, Page}
  alias Moss.Computer.Look

  @tabs 8
  @back 20

  def new, do: %{tabs: [], front: nil, cookies: Cookies.new(), screen: Look.screen()}

  @doc "The width and theme the computer's app is laid out at (`open app --width N --dark`)."
  def screen(%{browser: b}), do: Map.get(b, :screen) || Look.screen()

  def front(%{browser: %{tabs: tabs, front: n}}) when is_integer(n), do: Enum.at(tabs, n)
  def front(_), do: nil

  @doc "The page in a new tab: `{state, note}`, the note telling of a tab closed to make room."
  def open(state, page) do
    b = state.browser
    tab = %{url: page.url, page: page, history: [], ui_at: nil, values: %{}}

    {tabs, note} =
      if length(b.tabs) >= @tabs,
        do:
          {tl(b.tabs) ++ [tab], "(closed the oldest tab, #{hd(b.tabs).url}: #{@tabs} at most)\n"},
        else: {b.tabs ++ [tab], ""}

    {%{state | browser: %{b | tabs: tabs, front: length(tabs) - 1}}, note}
  end

  @doc "The page in the front tab, the page before kept as an address."
  def go(state, page) do
    tab = front(state)

    entry = %{
      url: tab.url,
      page: if(tab.page && tab.page.answer, do: Page.slim(tab.page), else: nil)
    }

    put(state, %{
      tab
      | url: page.url,
        page: page,
        history: Enum.take([entry | tab.history], @back),
        ui_at: nil
    })
  end

  def put(state, tab) do
    b = state.browser
    %{state | browser: %{b | tabs: List.replace_at(b.tabs, b.front, tab)}}
  end

  def close(state, n) do
    b = state.browser

    case Enum.at(b.tabs, n) do
      nil ->
        {:error, "no tab #{n + 1}"}

      tab ->
        tabs = List.delete_at(b.tabs, n)
        front = if tabs == [], do: nil, else: min(b.front, length(tabs) - 1)
        {:ok, tab, %{state | browser: %{b | tabs: tabs, front: front}}}
    end
  end

  def kept(b) do
    %{
      front: b.front,
      cookies: b.cookies,
      screen: Map.get(b, :screen),
      tabs:
        for t <- b.tabs do
          page = t.page

          %{
            url: t.url,
            values: if(page, do: typed(page), else: t.values),
            answer: page && page.answer && Page.slim(page),
            history: for(h <- t.history, do: %{url: h.url, page: h.page})
          }
        end
    }
  end

  def restore(nil), do: new()

  def restore(kept) do
    tabs =
      for t <- Map.get(kept, :tabs, []) do
        # a session kept before the browser feature held whole pages: only their addresses come back
        old = Map.get(t, :page)
        url = Map.get(t, :url) || (old && old.url)

        %{
          url: url,
          page: Map.get(t, :answer) || nil,
          values: Map.get(t, :values) || (old && Map.get(old, :values)) || %{},
          history: for(h <- Map.get(t, :history, []), do: %{url: h.url, page: h_page(h)}),
          ui_at: nil
        }
      end

    %{
      tabs: tabs,
      front: Map.get(kept, :front),
      cookies: Map.get(kept, :cookies) || Cookies.new(),
      screen: Map.get(kept, :screen) || Look.screen()
    }
  end

  defp h_page(%{page: %Page{answer: true} = p}), do: p
  defp h_page(_), do: nil

  # the fields the agent changed from what the page came with
  defp typed(page) do
    for c <- page.controls,
        v = Map.get(page.values, c.id),
        v != c.value,
        into: %{},
        do: {c.id, v}
  end
end

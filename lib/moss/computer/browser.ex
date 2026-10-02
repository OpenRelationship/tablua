defmodule Moss.Computer.Browser do
  @moduledoc """
  The computer's browser, headless: pages fetched by `Browser.Nav`, kept light in bounded tabs (`Browser.Tabs`),
  read in parts (`Page.Parts`), and drawn only when a person watches. The shell drives it; `help open` prints:
  """
  alias Moss.Computer.{Cookies, Page}
  alias Moss.Computer.Browser.{Nav, Tabs}
  alias Moss.Computer.Page.{Data, Parts}

  @help """
  The browser (no page scripts run; a page drawn only by its scripts reads as nearly empty, but `data` may
  hold what it shows):
    open <address>          a page in a new tab, as a map: headings numbered, regions, the first screen
    page [n]                part n of the main content     page nav|footer|aside|banner   a region's words
    page find <words>       the lines that hold the words  read <n|words>   one section under its heading
    ui [more|nav|<words>]   the controls, main content first, fifty at a time, each with an id
    click <id|words>        follows a link, or presses a button (a submit button sends its form)
    type <id|words> <text>  puts text in a field           submit [id|words]   sends a form
    back   tabs   close [n] the page before, the open tabs (eight at most), closing one
    data [n [path|find <words>]]   the JSON the page carries (JSON-LD, __NEXT_DATA__ ...), read by path
    cookies [clear [site]]  the sites with cookies, by name (never their values), or forgetting them
  A password field is the person's: the browser never types into one.
  `open app` opens the computer's own pages (`ui/*.lui` and its apps', at http://app/), as its person sees it.
  """

  @names ~w(open page read ui click type submit back tabs close data cookies)
  def names, do: @names
  def help, do: @help

  def new, do: Tabs.new()
  def front(state), do: Tabs.front(state)
  def kept(browser), do: Tabs.kept(browser)
  def restore(kept), do: Tabs.restore(kept)

  def run("open", ["app" <> rest | _], _stdin, state),
    do: Nav.go(state, "http://app/" <> String.trim_leading(rest, "/"), :new_tab)

  def run("open", [url | _], _stdin, state), do: Nav.go(state, url, :new_tab)
  def run("open", [], _stdin, state), do: {2, "", "open: needs an address\n", state}

  def run("tabs", _, _stdin, state) do
    out =
      state.browser.tabs
      |> Enum.with_index()
      |> Enum.map_join(fn {t, i} ->
        title = if t.page, do: t.page.title, else: "(not loaded)"
        "#{if i == state.browser.front, do: "*", else: " "} #{i + 1} #{title} — #{t.url}\n"
      end)

    {0, out, "", state}
  end

  def run("close", args, _stdin, state) do
    n =
      with [a | _] <- args,
           {i, ""} <- Integer.parse(a),
           do: i - 1,
           else: (_ -> state.browser.front || 0)

    case Tabs.close(state, n) do
      {:ok, tab, state} -> {0, "closed #{tab.url}\n", "", state}
      {:error, why} -> {1, "", "close: #{why}\n", state}
    end
  end

  def run("cookies", ["clear" | site], _stdin, state) do
    {0, "", "",
     put_in(state.browser.cookies, Cookies.clear(state.browser.cookies, List.first(site)))}
  end

  def run("cookies", _, _stdin, state) do
    case Cookies.list(state.browser.cookies, System.os_time(:second)) do
      [] ->
        {0, "no cookies\n", "", state}

      sites ->
        {0,
         Enum.map_join(sites, fn {d, names} -> "#{d}: #{Enum.join(Enum.uniq(names), ", ")}\n" end),
         "", state}
    end
  end

  def run(name, args, _stdin, state) do
    with %{} <- Tabs.front(state),
         {:ok, tab, state} <- Nav.load(state) do
      on_page(name, args, tab, state)
    else
      nil -> {1, "", "#{name}: no page is open (open <address>)\n", state}
      {:error, why} -> {6, "", "#{name}: #{why}\n", state}
    end
  end

  defp on_page("page", [], tab, state), do: {0, Parts.part(tab.page, 1), "", state}

  defp on_page("page", ["find" | words], tab, state) when words != [],
    do: {0, Parts.find(tab.page, Enum.join(words, " ")), "", state}

  defp on_page("page", [arg | _], tab, state) do
    case {Integer.parse(arg), Parts.region(arg)} do
      {{n, ""}, _} ->
        {0, Parts.part(tab.page, n), "", state}

      {_, r} when r != nil ->
        {0, Parts.of_region(tab.page, r), "", state}

      _ ->
        {2, "", "page: a part's number, a region (nav, footer, aside, banner), or find <words>\n",
         state}
    end
  end

  defp on_page("read", [], _tab, state), do: {2, "", "read: a heading's number or words\n", state}

  defp on_page("read", words, tab, state),
    do: {0, Parts.section(tab.page, Enum.join(words, " ")), "", state}

  defp on_page("ui", args, tab, state) do
    {filter, from} =
      case args do
        [] -> {nil, 0}
        ["more" | _] -> {elem(tab.ui_at || {nil, 0}, 0), elem(tab.ui_at || {nil, 0}, 1)}
        words -> {Parts.region(hd(words)) || Enum.join(words, " "), 0}
      end

    {out, next} = Parts.ui(tab.page, filter, from)
    {0, out, "", Tabs.put(state, %{tab | ui_at: next && {filter, next}})}
  end

  defp on_page("data", [], tab, state), do: {0, Data.list(tab.page.data), "", state}

  defp on_page("data", [n, "find" | words], tab, state) when words != [],
    do: answer(Data.find(tab.page.data, n, Enum.join(words, " ")), state)

  defp on_page("data", [n | path], tab, state),
    do: answer(Data.value(tab.page.data, n, Enum.join(path, "")), state)

  defp on_page("back", _, tab, state) do
    case tab.history do
      [%{page: %Page{} = prev} | older] ->
        {0, Parts.summary(prev), "",
         Tabs.put(state, %{tab | url: prev.url, page: prev, history: older, ui_at: nil})}

      [%{url: url} | older] ->
        state = Tabs.put(state, %{tab | url: url, page: nil, history: older, ui_at: nil})

        case Nav.load(state) do
          {:ok, tab, state} -> {0, Parts.summary(tab.page), "", state}
          {:error, why} -> {6, "", "back: #{why}\n", state}
        end

      [] ->
        {1, "", "back: this is the first page in the tab\n", state}
    end
  end

  defp on_page("click", [said | _], tab, state) do
    case Page.control(tab.page, said) do
      %{role: "link", href: href} when is_binary(href) ->
        Nav.go(state, Nav.resolve(tab.page, href), :same_tab, [], tab.page)

      %{role: "button", hx: {"GET", url}} ->
        Nav.go(state, Nav.resolve(tab.page, url), :same_tab, [], tab.page)

      %{role: "button", hx: {method, url}} = c ->
        pairs = if c.form > 0, do: Nav.form_pairs(tab.page, c), else: Nav.own_pair(c)
        pairs = pairs ++ (c.vals || [])
        Nav.act(state, tab, method, Nav.resolve(tab.page, url), pairs)

      %{role: "button", type: t} = c when t in ["submit", "image"] and c.form > 0 ->
        Nav.send_form(state, tab, c)

      %{role: box, type: t} = c
      when box in ["checkbox", "radio"] and t in ["checkbox", "radio"] ->
        {0, "", "", Tabs.put(state, %{tab | page: toggle(tab.page, c)})}

      %{role: "field"} = c ->
        {1, "", "click: [#{c.id}] is a field; type into it instead\n", state}

      %{} = c ->
        {0, "pressed \"#{c.name}\" (its script does not run here)\n", "", state}

      nil ->
        {1, "", "click: nothing on the page is \"#{said}\" (ui lists the controls)\n", state}
    end
  end

  defp on_page("type", [said | words], tab, state) when words != [] do
    case Page.control(tab.page, said) do
      %{role: "field", type: "password"} ->
        {1, "", "type: a password is the person's own to type; it was left empty\n", state}

      %{role: "field"} = c ->
        page = %{tab.page | values: Map.put(tab.page.values, c.id, Enum.join(words, " "))}

        {0, "[#{c.id}] \"#{c.name}\" = #{Enum.join(words, " ")}\n", "",
         Tabs.put(state, %{tab | page: page})}

      nil ->
        {1, "", "type: nothing on the page is \"#{said}\"\n", state}

      c ->
        {1, "", "type: [#{c.id}] is a #{c.role}, not a field\n", state}
    end
  end

  defp on_page("submit", args, tab, state) do
    c =
      if args == [],
        do: Enum.find(tab.page.controls, &(&1.form > 0)),
        else: Page.control(tab.page, hd(args))

    if c && c.form > 0,
      do: Nav.send_form(state, tab, c),
      else: {1, "", "submit: no form on the page\n", state}
  end

  defp on_page(name, _args, _tab, state), do: {2, "", "#{name}: needs more (help open)\n", state}

  defp answer({:ok, out}, state), do: {0, out, "", state}
  defp answer({:error, why}, state), do: {1, "", "data: #{why}\n", state}

  # a radio button turns the others of its name off; a checkbox flips
  defp toggle(page, %{type: "radio"} = c) do
    off = for o <- page.controls, o.type == "radio", o.field == c.field, into: %{}, do: {o.id, ""}
    %{page | values: page.values |> Map.merge(off) |> Map.put(c.id, "on")}
  end

  defp toggle(page, c),
    do: %{page | values: Map.update(page.values, c.id, "on", &if(&1 == "on", do: "", else: "on"))}
end

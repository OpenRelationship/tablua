defmodule MossWeb.ComputerLive do
  @moduledoc """
  An agent's computer, watched: a desktop drawn in the watcher's own browser
  from the computer's state, the only place its pixels exist. The Terminal shows
  every command the agent ran (live, from PubSub `computer:<id>`), the browser
  window the front page as the computer holds it (scripts off, in a sandboxed
  frame, with what the agent typed in its fields), Files the working folder.
  The person may type a command too; it runs as the agent's would.
  """
  use MossWeb, :live_view

  alias Moss.Computer
  alias Moss.Computer.{Browser, Page}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(Moss.PubSub, "computer:" <> id)

    {:ok,
     socket
     |> assign(id: id, page_title: "Computer " <> id, front: "terminal", line: "")
     |> refresh()}
  end

  @impl true
  def handle_info({:computer, _id, _entry}, socket), do: {:noreply, refresh(socket)}

  @impl true
  def handle_event("run", %{"line" => line}, socket) when line != "" do
    Computer.run(socket.assigns.id, line)
    {:noreply, socket |> assign(line: "") |> refresh()}
  end

  def handle_event("run", _, socket), do: {:noreply, socket}
  def handle_event("front", %{"window" => w}, socket), do: {:noreply, assign(socket, front: w)}

  defp refresh(socket) do
    view = Computer.view(socket.assigns.id)
    tab = Browser.front(%{browser: view.browser})

    files =
      case view.files,
        do: (
          {:ok, f} -> f
          _ -> []
        )

    assign(socket,
      cwd: view.cwd,
      lines: Enum.take(view.lines, -60),
      tabs: view.browser.tabs,
      front_tab: view.browser.front,
      page: tab && tab.page,
      page_html: tab && Page.html(tab.page),
      files: files,
      clock: Calendar.strftime(DateTime.utc_now(), "%a %H:%M")
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="computer fixed inset-0 overflow-hidden select-none font-sans text-[13px] text-stone-800">
      <%!-- the menu bar --%>
      <div class="absolute inset-x-0 top-0 z-30 flex h-7 items-center gap-5 bg-white/55 px-4 backdrop-blur-xl">
        <span class="font-semibold tracking-tight">◐ Arock</span>
        <span class="font-medium">{window_name(@front)}</span>
        <span class="text-stone-500">agent computer <span class="font-mono">{@id}</span></span>
        <span class="ml-auto tabular-nums text-stone-600">{@clock} UTC</span>
      </div>

      <%!-- Files --%>
      <.window
        id="files"
        title={"Files — " <> @cwd}
        front={@front}
        class="left-[3%] top-[9%] h-[46%] w-[22%]"
      >
        <ul class="divide-y divide-stone-100 overflow-auto">
          <li :for={f <- @files} class="flex items-center gap-2 px-3 py-1.5">
            <.icon
              name={if f.dir, do: "hero-folder-solid", else: "hero-document"}
              class={"size-4 " <> if(f.dir, do: "text-sky-500", else: "text-stone-400")}
            />
            <span class="truncate">{f.name}</span>
            <span :if={!f.dir} class="ml-auto tabular-nums text-stone-400">{size(f.size)}</span>
          </li>
          <li :if={@files == []} class="px-3 py-6 text-center text-stone-400">
            This folder is empty
          </li>
        </ul>
      </.window>

      <%!-- the browser --%>
      <.window
        id="browser"
        title={(@page && @page.title) || "Browser"}
        front={@front}
        class="left-[27%] top-[9%] h-[62%] w-[48%]"
      >
        <div class="flex items-center gap-2 border-b border-stone-200 bg-stone-50 px-3 py-1.5">
          <div class="flex min-w-0 flex-1 gap-1 overflow-hidden">
            <span
              :for={{t, i} <- Enum.with_index(@tabs)}
              class={"truncate rounded-md px-2 py-0.5 max-w-40 " <> if(i == @front_tab, do: "bg-white shadow-sm", else: "text-stone-500")}
            >
              {t.page.title}
            </span>
          </div>
        </div>
        <div class="border-b border-stone-200 px-3 py-1.5">
          <div class="truncate rounded-md bg-stone-100 px-3 py-1 text-center text-stone-600">
            {(@page && @page.url) || "No page open"}
          </div>
        </div>
        <iframe
          :if={@page_html}
          srcdoc={@page_html}
          sandbox=""
          class="min-h-0 w-full flex-1 bg-white"
          title="the page the agent has open"
        >
        </iframe>
        <div :if={!@page_html} class="grid flex-1 place-items-center text-stone-400">
          The agent has no page open
        </div>
      </.window>

      <%!-- Terminal --%>
      <.window
        id="terminal"
        title={"Terminal — " <> @cwd}
        front={@front}
        dark
        class="left-[3%] top-[57%] h-[34%] w-[72%] lg:left-[77%] lg:top-[9%] lg:h-[82%] lg:w-[20%]"
      >
        <div
          id="terminal-lines"
          phx-hook=".Bottom"
          class="min-h-0 flex-1 overflow-auto px-3 py-2 font-mono text-[12px] leading-relaxed text-stone-200 select-text"
        >
          <div :for={l <- @lines} class="mb-1.5">
            <div>
              <span class="text-lime-300">agent</span><span class="text-stone-500">:{l.cwd}$</span> {l.line}
            </div>
            <pre :if={l.out != ""} class="whitespace-pre-wrap text-stone-300">{clip(l.out)}</pre>
            <pre :if={l.err != ""} class="whitespace-pre-wrap text-rose-300">{clip(l.err)}</pre>
          </div>
        </div>
        <form
          phx-submit="run"
          class="flex items-center gap-2 border-t border-white/10 px-3 py-2 font-mono text-[12px]"
        >
          <span class="text-stone-500">$</span>
          <input
            name="line"
            value={@line}
            autocomplete="off"
            spellcheck="false"
            class="flex-1 border-0 bg-transparent p-0 text-stone-100 outline-none focus:ring-0"
            placeholder="type a command"
          />
        </form>
      </.window>

      <%!-- the dock --%>
      <div class="absolute inset-x-0 bottom-2 z-30 flex justify-center">
        <div class="flex gap-2 rounded-2xl bg-white/45 px-3 py-2 shadow-lg backdrop-blur-xl">
          <button
            :for={
              {w, icon} <- [
                {"files", "hero-folder"},
                {"browser", "hero-globe-alt"},
                {"terminal", "hero-command-line"}
              ]
            }
            phx-click="front"
            phx-value-window={w}
            class={"grid size-11 place-items-center rounded-xl transition hover:-translate-y-1 " <> if(@front == w, do: "bg-white shadow", else: "bg-white/60")}
            title={window_name(w)}
          >
            <.icon name={icon} class="size-6 text-stone-700" />
          </button>
        </div>
      </div>
    </div>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".Bottom">
      export default { mounted() { this.el.scrollTop = this.el.scrollHeight }, updated() { this.el.scrollTop = this.el.scrollHeight } }
    </script>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :front, :string, required: true
  attr :class, :string, default: ""
  attr :dark, :boolean, default: false
  slot :inner_block, required: true

  defp window(assigns) do
    ~H"""
    <section
      phx-click="front"
      phx-value-window={@id}
      class={"absolute flex flex-col overflow-hidden rounded-xl border shadow-2xl " <> @class <> " " <>
        if(@dark, do: "border-black/40 bg-stone-900/95", else: "border-black/10 bg-white") <> " " <>
        if(@front == @id, do: "z-20", else: "z-10 opacity-95")}
    >
      <header class={"flex h-8 shrink-0 items-center gap-2 px-3 " <> if(@dark, do: "bg-stone-800 text-stone-300", else: "bg-stone-100 text-stone-600")}>
        <span class="size-3 rounded-full bg-[#ff5f57]"></span>
        <span class="size-3 rounded-full bg-[#febc2e]"></span>
        <span class="size-3 rounded-full bg-[#28c840]"></span>
        <span class="mx-auto truncate pr-12 text-xs font-medium">{@title}</span>
      </header>
      {render_slot(@inner_block)}
    </section>
    """
  end

  defp window_name("files"), do: "Files"
  defp window_name("browser"), do: "Browser"
  defp window_name(_), do: "Terminal"

  defp clip(s), do: if(String.length(s) > 4000, do: String.slice(s, 0, 4000) <> "\n…", else: s)

  defp size(n) when n < 1024, do: "#{n} B"
  defp size(n) when n < 1_048_576, do: "#{Float.round(n / 1024, 1)} KB"
  defp size(n), do: "#{Float.round(n / 1_048_576, 1)} MB"
end

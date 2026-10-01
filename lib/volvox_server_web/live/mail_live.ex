defmodule VolvoxServerWeb.MailLive do
  @moduledoc """
  The post, for a person (Volvox PROJECT.md §14.5): letters Jev held, to
  release or refuse; the senders Jev refused, screened until a person clears
  them; the routes, which a person sets; and the latest letters with Jev's
  word on each. Live from PubSub `mail`.
  """
  use VolvoxServerWeb, :live_view

  alias VolvoxServer.Mail

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(VolvoxServer.PubSub, "mail")
    {:ok, socket |> assign(page_title: "Post") |> refresh()}
  end

  @impl true
  def handle_info(:mail_changed, socket), do: {:noreply, refresh(socket)}

  @impl true
  def handle_event("release", %{"id" => id}, socket),
    do: decided(socket, Mail.release(String.to_integer(id)))

  def handle_event("refuse", %{"id" => id}, socket),
    do: decided(socket, Mail.refuse(String.to_integer(id)))

  def handle_event("unflag", %{"sender" => s}, socket) do
    Mail.unflag(s)
    {:noreply, refresh(socket)}
  end

  def handle_event("unroute", %{"sender" => s, "recipient" => r}, socket) do
    Mail.unroute(s, r)
    {:noreply, refresh(socket)}
  end

  def handle_event("route", %{"sender" => s, "recipient" => r, "mode" => m}, socket) do
    {s, r} = {String.trim(s), String.trim(r)}

    if s != "" and r != "" and m in ["audit", "screen"] do
      Mail.route(s, r, m)
      {:noreply, refresh(socket)}
    else
      {:noreply, put_flash(socket, :error, "A route needs a sender, a recipient and a mode.")}
    end
  end

  defp decided(socket, :ok), do: {:noreply, refresh(socket)}

  defp decided(socket, {:error, why}),
    do: {:noreply, socket |> put_flash(:error, why) |> refresh()}

  defp refresh(socket) do
    recent = Mail.recent(200)

    assign(socket,
      held: Enum.filter(recent, &(&1["state"] == "held")),
      recent: Enum.take(recent, 60),
      flagged: Mail.flagged(),
      routes: Mail.routes()
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} person={@person}>
      <div class="mb-6 flex items-baseline justify-between">
        <h1 class="text-xl font-semibold">The post</h1>
        <span class="text-sm text-slate-500">letters between agents, read by Jev</span>
      </div>

      <section id="held" class="mb-8">
        <h2 class="mb-2 text-sm font-semibold uppercase tracking-wide text-slate-500">
          Held for you ({length(@held)})
        </h2>
        <p :if={@held == []} class="text-sm text-slate-500">Nothing is waiting for a person.</p>
        <article
          :for={l <- @held}
          id={"held-#{l["id"]}"}
          class="mb-3 rounded-md border border-amber-200 bg-amber-50/60 p-4"
        >
          <div class="mb-1 flex flex-wrap items-baseline gap-x-3 text-sm">
            <span class="font-mono font-semibold">{l["sender"]}</span>
            <span class="text-slate-400">to</span>
            <span class="font-mono">{l["recipient"]}</span>
            <span class="ml-auto text-xs text-amber-800">{l["reason"]}</span>
          </div>
          <p class="mb-1 font-medium">{l["subject"]}</p>
          <pre class="mb-3 max-h-48 overflow-auto whitespace-pre-wrap text-sm text-slate-700">{l["body"]}</pre>
          <div class="flex gap-2">
            <button
              phx-click="release"
              phx-value-id={l["id"]}
              class="rounded-md bg-slate-900 px-3 py-1.5 text-sm font-medium text-white hover:bg-slate-700"
            >
              Deliver it
            </button>
            <button
              phx-click="refuse"
              phx-value-id={l["id"]}
              class="rounded-md border border-slate-300 bg-white px-3 py-1.5 text-sm font-medium hover:bg-slate-50"
            >
              Refuse it
            </button>
          </div>
        </article>
      </section>

      <div class="mb-8 grid gap-8 md:grid-cols-2">
        <section id="flagged">
          <h2 class="mb-2 text-sm font-semibold uppercase tracking-wide text-slate-500">
            Screened senders
          </h2>
          <p :if={@flagged == []} class="text-sm text-slate-500">Jev has refused no one.</p>
          <ul class="divide-y divide-slate-200 text-sm">
            <li :for={f <- @flagged} class="flex items-baseline gap-3 py-2">
              <span class="font-mono font-semibold">{f["sender"]}</span>
              <span class="truncate text-slate-500">{f["reason"]}</span>
              <button
                phx-click="unflag"
                phx-value-sender={f["sender"]}
                class="ml-auto shrink-0 text-xs font-medium text-slate-600 underline hover:text-slate-900"
              >
                Clear
              </button>
            </li>
          </ul>
        </section>

        <section id="routes">
          <h2 class="mb-2 text-sm font-semibold uppercase tracking-wide text-slate-500">Routes</h2>
          <ul class="mb-3 divide-y divide-slate-200 text-sm">
            <li :for={r <- @routes} class="flex items-baseline gap-2 py-2">
              <span class="font-mono">{r["sender"]}</span>
              <span class="text-slate-400">→</span>
              <span class="font-mono">{r["recipient"]}</span>
              <span class={[
                "rounded px-1.5 text-xs",
                if(r["mode"] == "screen",
                  do: "bg-amber-100 text-amber-800",
                  else: "bg-slate-100 text-slate-600"
                )
              ]}>
                {r["mode"]}
              </span>
              <button
                phx-click="unroute"
                phx-value-sender={r["sender"]}
                phx-value-recipient={r["recipient"]}
                class="ml-auto text-xs font-medium text-slate-600 underline hover:text-slate-900"
              >
                Remove
              </button>
            </li>
            <li :if={@routes == []} class="py-2 text-slate-500">
              No routes: no agent can write to another.
            </li>
          </ul>
          <form id="route-form" phx-submit="route" class="flex flex-wrap items-center gap-2 text-sm">
            <input
              name="sender"
              placeholder="from (or *)"
              class="w-32 rounded-md border border-slate-300 bg-white px-2 py-1 font-mono text-sm"
            />
            <input
              name="recipient"
              placeholder="to (or *)"
              class="w-32 rounded-md border border-slate-300 bg-white px-2 py-1 font-mono text-sm"
            />
            <select name="mode" class="rounded-md border border-slate-300 bg-white px-2 py-1 text-sm">
              <option value="audit">audit</option>
              <option value="screen">screen</option>
            </select>
            <button class="rounded-md border border-slate-300 bg-white px-3 py-1 font-medium hover:bg-slate-50">
              Add route
            </button>
          </form>
        </section>
      </div>

      <section id="letters">
        <h2 class="mb-2 text-sm font-semibold uppercase tracking-wide text-slate-500">
          Latest letters
        </h2>
        <table class="w-full table-fixed border-collapse text-sm">
          <thead>
            <tr class="border-b border-slate-300 text-left text-xs uppercase tracking-wide text-slate-500">
              <th class="w-12 py-2 pr-3 text-right">#</th>
              <th class="w-32 py-2 pr-3">From</th>
              <th class="w-32 py-2 pr-3">To</th>
              <th class="py-2 pr-3">Subject</th>
              <th class="w-24 py-2 pr-3">State</th>
              <th class="w-40 py-2">Jev</th>
            </tr>
          </thead>
          <tbody>
            <tr :for={l <- @recent} class="border-b border-slate-100 align-top">
              <td class="py-1.5 pr-3 text-right tabular-nums text-slate-400">{l["id"]}</td>
              <td class="truncate py-1.5 pr-3 font-mono">{l["sender"]}</td>
              <td class="truncate py-1.5 pr-3 font-mono">{l["recipient"]}</td>
              <td class="truncate py-1.5 pr-3" title={l["reason"]}>{l["subject"]}</td>
              <td class={["py-1.5 pr-3", state_class(l["state"])]}>{l["state"]}</td>
              <td class="truncate py-1.5 text-slate-500">{l["verdict"] || l["reason"]}</td>
            </tr>
          </tbody>
        </table>
      </section>
    </Layouts.app>
    """
  end

  defp state_class("refused"), do: "text-rose-700"
  defp state_class("held"), do: "text-amber-700"
  defp state_class("screening"), do: "text-slate-500"
  defp state_class(_), do: "text-emerald-700"
end

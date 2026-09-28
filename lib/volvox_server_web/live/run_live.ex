defmodule VolvoxServerWeb.RunLive do
  @moduledoc """
  One run, live: its log as Robot rows (keyword, arguments, actor), streamed
  from PubSub `run:<id>` as the run appends, and each task's place in its plan
  machine. Opening the page wakes the run if it is asleep; the page itself
  never writes, since the UI is host-owned and steers only by appending.
  """
  use VolvoxServerWeb, :live_view

  alias VolvoxServer.Run

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket), do: Phoenix.PubSub.subscribe(VolvoxServer.PubSub, "run:" <> id)
    {:ok, _} = Run.wake(id)
    %{events: events, tasks: tasks} = Run.snapshot(id)

    {:ok,
     socket
     |> assign(id: id, page_title: "Run " <> id, count: length(events), machines: %{})
     |> assign_tasks(tasks)
     |> stream_configure(:events, dom_id: &"event-#{&1.seq}")
     |> stream(:events, events)}
  end

  @impl true
  def handle_info({:event, event}, socket) do
    {:noreply, socket |> update(:count, &max(&1, event.seq)) |> stream_insert(:events, event)}
  end

  def handle_info({:tasks, tasks}, socket), do: {:noreply, assign_tasks(socket, tasks)}

  # Each machine's states are read once, from the core's plan.machines.
  defp assign_tasks(socket, tasks) do
    machines =
      Enum.reduce(tasks, socket.assigns.machines, fn %{machine: m}, acc ->
        Map.put_new_lazy(acc, m, fn -> states(m) end)
      end)

    assign(socket, tasks: tasks, machines: machines)
  end

  defp states(nil), do: nil

  defp states(machine) do
    case VolvoxServer.Lua.call(:machine, [machine], []) do
      {:ok, [nil]} -> nil
      {:ok, [states]} -> VolvoxServer.Lua.list(states)
      {:error, _} -> nil
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="mb-6 flex items-baseline justify-between">
        <h1 class="text-xl font-semibold">Run <span class="font-mono">{@id}</span></h1>
        <span class="text-sm text-slate-500">{@count} events</span>
      </div>

      <section id="tasks" class="mb-8 space-y-3">
        <p :if={@tasks == []} class="text-sm text-slate-500">No task has started.</p>
        <div
          :for={t <- @tasks}
          id={"task-#{t.task}"}
          class="rounded-md border border-slate-200 bg-white p-4"
        >
          <div class="mb-3 flex flex-wrap items-baseline gap-x-4 gap-y-1">
            <span class="font-mono font-semibold">{t.task}</span>
            <span class="text-sm text-slate-500">{t.machine}</span>
            <span :if={t.result} class={["text-sm font-medium", result_class(t.result)]}>
              tests: {t.result}
            </span>
          </div>
          <ol class="flex flex-wrap gap-2">
            <li
              :for={s <- @machines[t.machine] || [t.state]}
              class={[
                "rounded-full border px-3 py-1 font-mono text-xs",
                if(s == t.state,
                  do: "current border-sky-600 bg-sky-600 text-white",
                  else: "border-slate-200 text-slate-600"
                )
              ]}
            >
              {s}
            </li>
          </ol>
        </div>
      </section>

      <table class="w-full table-fixed border-collapse text-sm">
        <thead>
          <tr class="border-b border-slate-300 text-left text-xs uppercase tracking-wide text-slate-500">
            <th class="w-14 py-2 pr-3 text-right">Seq</th>
            <th class="w-24 py-2 pr-3">Task</th>
            <th class="w-44 py-2 pr-3">Keyword</th>
            <th class="py-2 pr-3">Arguments</th>
            <th class="w-16 py-2">Actor</th>
          </tr>
        </thead>
        <tbody id="events" phx-update="stream">
          <tr
            :for={{dom_id, e} <- @streams.events}
            id={dom_id}
            class={["border-b border-slate-100 align-top", row_class(e)]}
          >
            <td class="py-1.5 pr-3 text-right font-mono text-xs text-slate-400">{e.seq}</td>
            <td class="truncate py-1.5 pr-3 font-mono text-xs">{e.task}</td>
            <td class="py-1.5 pr-3 font-semibold">{e.keyword}</td>
            <td class="py-1.5 pr-3">
              <span
                :for={a <- e.args}
                class="mr-2 inline-block max-w-full whitespace-pre-wrap break-all rounded bg-slate-100 px-1.5 font-mono text-xs"
              >
                {a}
              </span>
            </td>
            <td class={["py-1.5 text-xs", actor_class(e.actor)]}>{e.actor}</td>
          </tr>
        </tbody>
      </table>
    </Layouts.app>
    """
  end

  defp result_class("pass"), do: "text-emerald-700"
  defp result_class(_), do: "text-red-700"

  defp row_class(%{keyword: k}) when k in ["Action Failed", "Decide Failed", "Out Of Budget"],
    do: "bg-red-50"

  defp row_class(_), do: nil

  defp actor_class("user"), do: "font-medium text-violet-700"
  defp actor_class("host"), do: "text-amber-700"
  defp actor_class(_), do: "text-slate-500"
end

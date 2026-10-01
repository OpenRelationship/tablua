defmodule VolvoxServerWeb.Layouts do
  @moduledoc "The root document and the app frame around every page."
  use VolvoxServerWeb, :html

  embed_templates "layouts/*"

  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :person, :string, default: nil, doc: "the signed-in person, who may sign out"
  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="flex items-center border-b border-slate-200 bg-white px-6 py-3">
      <span class="font-semibold tracking-tight">Volvox</span>
      <.link
        :if={@person}
        href="/logout"
        method="delete"
        class="ml-auto text-sm text-slate-500 hover:text-slate-900"
      >
        Sign out {@person}
      </.link>
    </header>
    <main class="mx-auto max-w-6xl px-6 py-8">
      {render_slot(@inner_block)}
    </main>
    <.flash_group flash={@flash} />
    """
  end

  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
      <.flash
        id="client-error"
        kind={:error}
        title="We can't find the internet"
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
      </.flash>
      <.flash
        id="server-error"
        kind={:error}
        title="Something went wrong!"
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        Attempting to reconnect
      </.flash>
    </div>
    """
  end
end

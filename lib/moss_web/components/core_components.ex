defmodule MossWeb.CoreComponents do
  @moduledoc "The few UI pieces the pages share: flash notices and Heroicons, in plain Tailwind."
  use Phoenix.Component

  alias Phoenix.LiveView.JS

  @doc "A flash notice; click to dismiss."
  attr :id, :string, doc: "the optional id of flash container"
  attr :flash, :map, default: %{}, doc: "the map of flash messages to display"
  attr :title, :string, default: nil
  attr :kind, :atom, values: [:info, :error], doc: "used for styling and flash lookup"
  attr :rest, :global, doc: "the arbitrary HTML attributes to add to the flash container"
  slot :inner_block, doc: "the optional inner block that renders the flash message"

  def flash(assigns) do
    assigns = assign_new(assigns, :id, fn -> "flash-#{assigns.kind}" end)

    ~H"""
    <div
      :if={msg = render_slot(@inner_block) || Phoenix.Flash.get(@flash, @kind)}
      id={@id}
      phx-click={JS.push("lv:clear-flash", value: %{key: @kind}) |> hide("##{@id}")}
      role="alert"
      class={[
        "fixed top-4 right-4 z-50 flex max-w-sm gap-3 rounded-md border px-4 py-3 text-sm shadow",
        @kind == :info && "border-sky-200 bg-sky-50 text-sky-900",
        @kind == :error && "border-red-200 bg-red-50 text-red-900"
      ]}
      {@rest}
    >
      <.icon :if={@kind == :info} name="hero-information-circle" class="size-5 shrink-0" />
      <.icon :if={@kind == :error} name="hero-exclamation-circle" class="size-5 shrink-0" />
      <div>
        <p :if={@title} class="font-semibold">{@title}</p>
        <p>{msg}</p>
      </div>
      <button type="button" class="cursor-pointer self-start" aria-label="close">
        <.icon name="hero-x-mark" class="size-5 opacity-50 hover:opacity-100" />
      </button>
    </div>
    """
  end

  @doc "A Heroicon, e.g. `<.icon name=\"hero-x-mark\" />`."
  attr :name, :string, required: true
  attr :class, :any, default: "size-4"

  def icon(%{name: "hero-" <> _} = assigns) do
    ~H"""
    <span class={[@name, @class]} />
    """
  end

  def show(js \\ %JS{}, selector) do
    JS.show(js,
      to: selector,
      time: 300,
      transition: {"transition-all ease-out duration-300", "opacity-0", "opacity-100"}
    )
  end

  def hide(js \\ %JS{}, selector) do
    JS.hide(js,
      to: selector,
      time: 200,
      transition: {"transition-all ease-in duration-200", "opacity-100", "opacity-0"}
    )
  end
end

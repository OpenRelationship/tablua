defmodule VolvoxServerWeb.MacChannel do
  @moduledoc """
  One Mac online (`VolvoxServer.Mac`): joining sends it what is waiting; work
  comes as a `work` push (`id`, `run`, `task`, `request`), and the Mac answers
  `done` with `id` and `result`.
  """
  use Phoenix.Channel

  alias VolvoxServer.Mac

  @impl true
  def join("mac:" <> owner, _params, socket) do
    if owner == socket.assigns.owner do
      send(self(), :online)
      {:ok, socket}
    else
      {:error, %{reason: "not your Mac"}}
    end
  end

  @impl true
  def handle_info(:online, socket) do
    :ok = Mac.online(socket.assigns.owner)
    {:noreply, socket}
  end

  def handle_info({:work, work}, socket) do
    push(socket, "work", work)
    {:noreply, socket}
  end

  @impl true
  def handle_in("done", %{"id" => id, "result" => result}, socket)
      when is_integer(id) and is_binary(result) do
    case Mac.done(socket.assigns.owner, id, result) do
      :ok -> {:reply, :ok, socket}
      {:error, reason} -> {:reply, {:error, %{reason: to_string(reason)}}, socket}
    end
  end
end

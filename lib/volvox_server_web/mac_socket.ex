defmodule VolvoxServerWeb.MacSocket do
  @moduledoc """
  The Pet Rock app's socket. It connects with `token`, one of config
  `mac_tokens` (token => owner), and may join only its owner's `mac:` topic.
  """
  use Phoenix.Socket

  channel "mac:*", VolvoxServerWeb.MacChannel

  @impl true
  def connect(%{"token" => token}, socket, _info) when is_binary(token) do
    tokens = Application.get_env(:volvox_server, :mac_tokens, %{})

    case Enum.find(tokens, fn {t, _} -> Plug.Crypto.secure_compare(t, token) end) do
      {_, owner} -> {:ok, assign(socket, :owner, owner)}
      nil -> :error
    end
  end

  def connect(_params, _socket, _info), do: :error

  @impl true
  def id(socket), do: "mac:" <> socket.assigns.owner
end

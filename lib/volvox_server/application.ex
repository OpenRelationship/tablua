defmodule VolvoxServer.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    # The core's base Lua state, built once for every run on this node.
    VolvoxServer.Lua.base()

    children = [
      VolvoxServerWeb.Telemetry,
      {Phoenix.PubSub, name: VolvoxServer.PubSub},
      {Registry, keys: :unique, name: VolvoxServer.Colm.Registry},
      {DynamicSupervisor, name: VolvoxServer.Colm.Supervisor, strategy: :one_for_one},
      {Registry, keys: :unique, name: VolvoxServer.Run.Registry},
      {DynamicSupervisor, name: VolvoxServer.Run.Supervisor, strategy: :one_for_one},
      VolvoxServerWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: VolvoxServer.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    VolvoxServerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

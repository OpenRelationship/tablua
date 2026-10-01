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
      VolvoxServer.Schedule,
      VolvoxServer.Mac,
      VolvoxServerWeb.Endpoint
    ]

    # Runs that were awake when the node stopped wake again and finish what they were driving.
    children =
      if Application.get_env(:volvox_server, :wake_on_boot, true),
        do: children ++ [{Task, &VolvoxServer.Run.wake_working/0}],
        else: children

    Supervisor.start_link(children, strategy: :one_for_one, name: VolvoxServer.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    VolvoxServerWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

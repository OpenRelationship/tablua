defmodule Moss.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    # The core's base Lua state (Jev for the post), built once on this node.
    Moss.Lua.base()

    Moss.Computer.Programs.table()

    children = [
      MossWeb.Telemetry,
      {Phoenix.PubSub, name: Moss.PubSub},
      {Registry, keys: :unique, name: Moss.Computer.Registry},
      {DynamicSupervisor, name: Moss.Computer.Supervisor, strategy: :one_for_one},
      Supervisor.child_spec({Task, &Moss.Computer.Programs.warm/0}, id: :warm_programs),
      Moss.Mail,
      MossWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Moss.Supervisor)
  end

  @impl true
  def config_change(changed, _new, removed) do
    MossWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end

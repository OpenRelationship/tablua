defmodule Moss.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    # The core's base Lua state (Jev for the post), built once on this node.
    Moss.Lua.base()

    # Every module now, as a release loads them: a computer's kept session names their atoms (Disk.kept/3)
    for m <- Application.spec(:moss, :modules), do: Code.ensure_loaded(m)

    children = [
      MossWeb.Telemetry,
      {Phoenix.PubSub, name: Moss.PubSub},
      {Registry, keys: :unique, name: Moss.Computer.Registry},
      {DynamicSupervisor, name: Moss.Computer.Supervisor, strategy: :one_for_one},
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

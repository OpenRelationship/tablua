defmodule Moss.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    # The core's base Lua state, built once on this node.
    Moss.Lua.base()

    # Every module now, as a release loads them: a computer's kept session names their atoms (Moss.Computer.Session.kept/2)
    for m <- Application.spec(:moss, :modules), do: Code.ensure_loaded(m)

    # the node's compiled .lui pages (Moss.Computer.Script), owned by this process for the node's life
    Moss.Computer.Script.compiled_table()

    # The computers and what they tell their watchers (a computer's commands, its home, its mail), on Moss.PubSub;
    # the host (Moss.Host) starts its own services beside these.
    children =
      [
        {Phoenix.PubSub, name: Moss.PubSub},
        {Registry, keys: :unique, name: Moss.Computer.Registry},
        {DynamicSupervisor, name: Moss.Computer.Supervisor, strategy: :one_for_one}
      ] ++ Moss.Computer.Look.children()

    Supervisor.start_link(children, strategy: :one_for_one, name: Moss.Supervisor)
  end
end

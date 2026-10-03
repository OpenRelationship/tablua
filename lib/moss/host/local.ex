defmodule Moss.Host.Local do
  @moduledoc """
  A moss on its own, with no server (`Moss.Host`): its file stays where it is between wakes, it has no post and
  no names but its own, and its model keys come from the environment. MOSS's own tests run on it; on a node,
  arock-server is the host instead.
  """
  @behaviour Moss.Host
  alias Moss.Computer.Disk

  @impl true
  def pull(_id, _path), do: :ok

  @impl true
  def sleep(state), do: Disk.close(state.disk)

  @impl true
  def cut(state), do: {:ok, state}

  @impl true
  def streamed?, do: false

  @impl true
  def post(_id, _to, _subject, _body), do: {:refused, "this computer runs on its own: it has no post"}

  @impl true
  def inbox(_id), do: []

  @impl true
  def inbox_except(_id, _except), do: []

  @impl true
  def read(_id, _letter), do: {:error, :no_post}

  @impl true
  def sent(_id), do: []

  @impl true
  def board(_id), do: "no tasks: this computer runs on its own\n"

  @impl true
  def resolve(address), do: {:error, "#{address} names nothing: this computer runs on its own"}

  @impl true
  def computer(_id), do: :ok

  @impl true
  def manifest(_id, _path, _text), do: :ok

  @impl true
  def gone(_id, _path), do: :ok

  @keys %{
    "jev" => "OPENROUTER_API_KEY",
    "mercury" => "INCEPTION_API_KEY",
    "tabpfn" => "PRIORLABS_API_KEY"
  }

  @impl true
  def key(name) do
    case System.get_env(Map.get(@keys, name, "")) do
      v when is_binary(v) and v != "" -> v
      _ -> nil
    end
  end

  # on its own a computer calls the providers with the environment's keys
  @impl true
  def service(_id), do: nil
end

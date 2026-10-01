defmodule Moss.Objects do
  @moduledoc """
  Where a sleeping computer's SQLite disk lives: an object store keyed like
  `computers/<id>.sqlite`. Two adapters implement the behaviour:
  `Objects.Service` (Arock's service, which keeps them in R2 and serves this
  node only the disks it claimed, by the node's own token: no key to the bucket
  or the account is on the node) and `Objects.Local` (a directory; the test
  double, and the fallback when the node has no token).

  Config `objects:` is `:service`, `:local`, or `:auto`, which uses the service
  when the node has a token and the local directory otherwise, decided once per node.
  """

  @callback get(key :: String.t()) :: {:ok, binary()} | :not_found | {:error, term()}
  @callback put(key :: String.t(), body :: binary()) :: :ok | {:error, term()}
  @callback delete(key :: String.t()) :: :ok | {:error, term()}

  alias Moss.Objects.{Local, Service}

  def get(key), do: adapter().get(key)
  def put(key, body), do: adapter().put(key, body)
  def delete(key), do: adapter().delete(key)

  def adapter do
    case Application.fetch_env!(:moss, :objects) do
      :local -> Local
      :service -> Service
      :auto -> auto()
    end
  end

  defp auto do
    case :persistent_term.get({__MODULE__, :auto}, nil) do
      nil ->
        adapter = if Service.available?(), do: Service, else: Local
        :persistent_term.put({__MODULE__, :auto}, adapter)
        adapter

      adapter ->
        adapter
    end
  end

  @doc "The key of a computer's disk."
  def computer_key(id), do: "computers/#{id}.sqlite"
end

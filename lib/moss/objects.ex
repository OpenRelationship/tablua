defmodule Moss.Objects do
  @moduledoc """
  Where a sleeping computer's SQLite disk lives: an object store keyed like
  `computers/<id>.sqlite`. Two adapters implement the behaviour:
  `Objects.Service` (Arock's service, which keeps them in R2 and serves this
  node only the disks it claimed, by the node's own token: no key to the bucket
  or the account is on the node) and `Objects.Local` (a directory; the test
  double, and the fallback when the node has no token).

  A computer's log (its file as Litestream streams it, Arock PROJECT.md §15)
  is kept beside its disk as segments, `log_*`, under the same claim.

  Config `objects:` is `:service`, `:local`, or `:auto`, which uses the service
  when the node has a token and the local directory otherwise, decided once per node.
  """

  @callback get(key :: String.t()) :: {:ok, binary()} | :not_found | {:error, term()}
  @callback put(key :: String.t(), body :: binary()) :: :ok | {:error, term()}
  @callback delete(key :: String.t()) :: :ok | {:error, term()}

  # A computer's log as Litestream writes it (`Moss.Objects.Shipper`): segments named `<level>/<min>-<max>.ltx`.
  @callback log_list(id :: String.t()) ::
              {:ok, %{String.t() => non_neg_integer()}} | {:error, term()}
  @callback log_get(id :: String.t(), name :: String.t()) ::
              {:ok, binary()} | :not_found | {:error, term()}
  @callback log_put(id :: String.t(), name :: String.t(), body :: binary()) ::
              :ok | {:error, term()}
  @callback log_delete(id :: String.t(), name :: String.t()) :: :ok | {:error, term()}

  alias Moss.Objects.{Local, Service}

  def get(key), do: adapter().get(key)
  def put(key, body), do: adapter().put(key, body)
  def delete(key), do: adapter().delete(key)
  def log_list(id), do: adapter().log_list(id)
  def log_get(id, name), do: adapter().log_get(id, name)
  def log_put(id, name, body), do: adapter().log_put(id, name, body)
  def log_delete(id, name), do: adapter().log_delete(id, name)

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

  @doc "Whether `name` is a log segment's name, `<level>/<16 hex>-<16 hex>.ltx`, as the service checks it."
  def segment?(name),
    do: is_binary(name) and Regex.match?(~r/\A\d{1,2}\/[0-9a-f]{16}-[0-9a-f]{16}\.ltx\z/, name)
end

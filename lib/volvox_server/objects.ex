defmodule VolvoxServer.Objects do
  @moduledoc """
  Where a sleeping run's SQLite file lives: an object store keyed like
  `runs/<id>.sqlite`. Two adapters implement the behaviour: `Objects.R2`
  (Cloudflare R2 over its REST API, with wrangler's OAuth token) and
  `Objects.Local` (a directory; the test double, and the fallback when
  wrangler is not logged in).

  Config `objects:` is `:r2`, `:local`, or `:auto`, which uses R2 when wrangler
  hands out a token and the local directory otherwise, decided once per node.
  """

  @callback get(key :: String.t()) :: {:ok, binary()} | :not_found | {:error, term()}
  @callback put(key :: String.t(), body :: binary()) :: :ok | {:error, term()}
  @callback delete(key :: String.t()) :: :ok | {:error, term()}

  alias VolvoxServer.Objects.{Local, R2}

  def get(key), do: adapter().get(key)
  def put(key, body), do: adapter().put(key, body)
  def delete(key), do: adapter().delete(key)

  def adapter do
    case Application.fetch_env!(:volvox_server, :objects) do
      :local -> Local
      :r2 -> R2
      :auto -> auto()
    end
  end

  defp auto do
    case :persistent_term.get({__MODULE__, :auto}, nil) do
      nil ->
        adapter = if R2.available?(), do: R2, else: Local
        :persistent_term.put({__MODULE__, :auto}, adapter)
        adapter

      adapter ->
        adapter
    end
  end

  @doc "The key of a run's file."
  def run_key(id), do: "runs/#{id}.sqlite"
end

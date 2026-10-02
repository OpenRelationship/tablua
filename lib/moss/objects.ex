defmodule Moss.Objects do
  @moduledoc """
  Where a sleeping computer's SQLite disk lives: an object store keyed like
  `computers/<id>.sqlite`. Two adapters implement the behaviour:
  `Objects.Service` (Arock's service, which keeps them in R2 and serves this
  node only the disks it claimed, by the node's own token: no key to the bucket
  or the account is on the node) and `Objects.Local` (a directory; the test
  double, and the fallback when the node has no token).

  A sleeping computer is its whole disk. While computers are awake, the node
  keeps their recent work as packs (`pack_*`, `Moss.Objects.Packer`, Arock
  PROJECT.md §15 item 4) under its own prefix, the node's name
  (`node_name/0`). A computer that slept before packs is its log's segments,
  read only (`log_*`, `Moss.Objects.Legacy`) until its next sleep.

  Config `objects:` is `:service`, `:local`, or `:auto`, which uses the service
  when the node has a token and the local directory otherwise, decided once per node.
  """

  @callback get(key :: String.t()) :: {:ok, binary()} | :not_found | {:error, term()}
  @callback put(key :: String.t(), body :: binary()) :: :ok | {:error, term()}
  @callback delete(key :: String.t()) :: :ok | {:error, term()}

  # A computer's log from before packs, read only: segments named `<level>/<min>-<max>.ltx`.
  @callback log_list(id :: String.t()) ::
              {:ok, %{String.t() => non_neg_integer()}} | {:error, term()}
  @callback log_get(id :: String.t(), name :: String.t()) ::
              {:ok, binary()} | :not_found | {:error, term()}

  # This node's packs (`Moss.Objects.Pack`), named `<16 hex>-<8 hex>.pack`; a range is `{first, last | nil}`.
  @callback pack_list() :: {:ok, %{String.t() => non_neg_integer()}} | {:error, term()}
  @callback pack_get(
              name :: String.t(),
              range :: nil | {non_neg_integer(), non_neg_integer() | nil}
            ) ::
              {:ok, binary()} | :not_found | {:error, term()}
  @callback pack_put(name :: String.t(), body :: binary()) :: :ok | {:error, term()}
  @callback pack_delete(name :: String.t()) :: :ok | {:error, term()}

  alias Moss.Objects.{Local, Service}

  def get(key), do: adapter().get(key)
  def put(key, body), do: adapter().put(key, body)
  def delete(key), do: adapter().delete(key)
  def log_list(id), do: adapter().log_list(id)
  def log_get(id, name), do: adapter().log_get(id, name)
  def pack_list, do: adapter().pack_list()
  def pack_get(name, range \\ nil), do: adapter().pack_get(name, range)
  def pack_put(name, body), do: adapter().pack_put(name, body)
  def pack_delete(name), do: adapter().pack_delete(name)

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

  @doc """
  This node's name, its packs' prefix: MOSS_NODE, else the account of the
  keychain item `moss-node-token` (`just tool worker node <name>` sets both),
  else `local`.
  """
  def node_name do
    case System.get_env("MOSS_NODE") do
      n when is_binary(n) and n != "" -> n
      _ -> :persistent_term.get({__MODULE__, :node}, nil) || keychain_node()
    end
  end

  defp keychain_node do
    name =
      case System.cmd("security", ["find-generic-password", "-s", "moss-node-token"],
             stderr_to_stdout: true
           ) do
        {out, 0} ->
          with [_, n] <- Regex.run(~r/"acct"<blob>="([a-z0-9-]+)"/, out),
               do: n,
               else: (_ -> "local")

        _ ->
          "local"
      end

    :persistent_term.put({__MODULE__, :node}, name)
    name
  rescue
    ErlangError -> "local"
  end

  @doc "Whether `name` is a log segment's name, `<level>/<16 hex>-<16 hex>.ltx`, as the service checks it."
  def segment?(name),
    do: is_binary(name) and Regex.match?(~r/\A\d{1,2}\/[0-9a-f]{16}-[0-9a-f]{16}\.ltx\z/, name)
end

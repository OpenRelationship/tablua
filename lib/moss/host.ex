defmodule Moss.Host do
  @moduledoc """
  What a computer needs from wherever it runs (Arock PROJECT.md §14, names): its file kept while it sleeps, the
  post, the node's names, and the model keys or Arock's service in their place. MOSS is the computer; the host is the server that runs it, Arock's
  arock-server on a node (`config :moss, host: ArockServer.Host`), or `Moss.Host.Local` for a moss on its own.

  A host implements every callback; the computer calls them through this module, so it never names the server.
  """

  @typedoc "A computer's GenServer state (`Moss.Computer`): `id`, `path`, `disk` and the rest."
  @type state :: map()

  @doc "Before a wake: the computer's file put at `path` from wherever it was kept, or left as it is."
  @callback pull(id :: String.t(), path :: String.t()) :: :ok | {:error, term()}
  @doc "A sleep: the disk closed and the file kept by the host; the files stay until it holds them."
  @callback sleep(state()) :: :ok | {:error, term()}
  @doc "An awake computer's snapshot: `{result, state}`, or `{:stop, why, state}` when its disk will not reopen."
  @callback cut(state()) :: {term(), state()} | {:stop, term(), state()}
  @doc "Whether the file is streamed while awake (its WAL and checkpoints the host's), so the disk leaves them alone."
  @callback streamed?() :: boolean()

  @doc "A letter from computer `id`: `{:delivered, n}`, `{:screening, n}` or `{:refused, why}`."
  @callback post(id :: String.t(), to :: String.t(), subject :: String.t(), body :: String.t()) :: term()
  @doc "The letters waiting for `id`, oldest first, each a map with \"id\", \"sender\", \"subject\" and \"body\"."
  @callback inbox(id :: String.t()) :: [map()]
  @doc "The inbox without the letters numbered in `except`."
  @callback inbox_except(id :: String.t(), except :: [integer()]) :: [map()]
  @doc "One letter of `id`'s inbox: `{:ok, letter}` or an error."
  @callback read(id :: String.t(), letter :: integer()) :: {:ok, map()} | term()
  @doc "The letters `id` sent."
  @callback sent(id :: String.t()) :: [map()]
  @doc "`id`'s board: its tasks and their letters, as text."
  @callback board(id :: String.t()) :: String.t()

  @doc """
  An `org:` address resolved for computer `from` without waking what it names: `{:ok, what}` or `{:error, why}`. A host
  with tenants answers only for `from`'s own tenant (Arock's uspx).
  """
  @callback resolve(from :: String.t(), address :: String.t()) :: {:ok, term()} | {:error, String.t()}
  @doc "A computer awake on this host, so its address resolves."
  @callback computer(id :: String.t()) :: term()
  @doc "A manifest written at `path`: the names it declares replace the ones it declared before."
  @callback manifest(id :: String.t(), path :: String.t(), text :: String.t()) :: term()
  @doc "A manifest removed: the names it declared go."
  @callback gone(id :: String.t(), path :: String.t()) :: term()

  @doc "A model key by name (\"jev\", \"mercury\"), or nil; given to the caller only, never logged."
  @callback key(name :: String.t()) :: String.t() | nil

  @doc """
  Arock's service for computer `id`'s model calls, or nil to use `key/1`: `%{"base" => url, "key" => token,
  "person" => account | nil}`. A node gives its own token and the person the computer is theirs, so it holds no
  provider key (Arock PROJECT.md §19); nil `id`, or no person, is the host's own work (the post's reading).
  """
  @callback service(id :: String.t() | nil) :: map() | nil

  @doc "The host this node's computers run on."
  def impl, do: Application.get_env(:moss, :host, Moss.Host.Local)

  def pull(id, path), do: impl().pull(id, path)
  def sleep(state), do: impl().sleep(state)
  def cut(state), do: impl().cut(state)
  def streamed?, do: impl().streamed?()
  def post(id, to, subject, body), do: impl().post(id, to, subject, body)
  def inbox(id), do: impl().inbox(id)
  def inbox_except(id, except), do: impl().inbox_except(id, except)
  def read(id, letter), do: impl().read(id, letter)
  def sent(id), do: impl().sent(id)
  def board(id), do: impl().board(id)
  def resolve(from, address), do: impl().resolve(from, address)
  def computer(id), do: impl().computer(id)
  def manifest(id, path, text), do: impl().manifest(id, path, text)
  def gone(id, path), do: impl().gone(id, path)
  def key(name), do: impl().key(name)
  def service(id), do: impl().service(id)
end

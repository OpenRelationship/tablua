defmodule Moss.Objects.Legacy do
  @moduledoc """
  A computer that slept before packs (Arock PROJECT.md §15 item 4) is its
  log's segments in the store, shipped one by one. They are read only now:
  such a computer wakes from them (`restore/2`) and at its next sleep is kept
  whole, so its segments are never read again. Nothing writes or deletes them.
  """
  alias Moss.{Litestream, Objects}

  @doc "Rebuilds computer `id`'s file at `out` from its old segments: `:ok`, `:none` when it has none, or an error."
  def restore(id, out) do
    with {:ok, remote} when remote != %{} <- Objects.log_list(id),
         {:ok, segments} <- download(id, Map.keys(remote)) do
      Litestream.rebuild(segments, out)
    else
      {:ok, %{}} -> :none
      {:error, _} = e -> e
    end
  end

  # every segment at once (a wake waits on it)
  defp download(id, names) do
    names
    |> Task.async_stream(fn name -> {name, Objects.log_get(id, name)} end,
      max_concurrency: Application.get_env(:moss, :restore_concurrency, 16),
      timeout: 120_000
    )
    |> Enum.reduce_while({:ok, %{}}, fn
      {:ok, {name, {:ok, body}}}, {:ok, acc} -> {:cont, {:ok, Map.put(acc, name, body)}}
      {:ok, {name, other}}, _ -> {:halt, {:error, {:restore, name, other}}}
      other, _ -> {:halt, {:error, {:restore, other}}}
    end)
  end
end

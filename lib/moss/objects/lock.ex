defmodule Moss.Objects.Lock do
  @moduledoc """
  A computer's lock on the node: a folder only one process makes, beside the
  replica (`.locks/<id>`), so it holds across the BEAMs on one work dir (a node
  and a mix task beside it). A wake, a sleep and the packer's reading of a
  computer's segments each hold it. A lock whose holder is gone is taken over.
  """
  alias Moss.Litestream

  @doc "Runs `fun` holding computer `id`'s lock: `wait` `:infinity` waits for it, `0` gives `:busy` at once."
  def locked(id, wait, fun) do
    case take(id, wait) do
      :ok ->
        try do
          fun.()
        after
          release(id)
        end

      :busy ->
        :busy
    end
  end

  @doc "Takes computer `id`'s lock: `:ok`, or `:busy` when `wait` is 0 and another holds it."
  def take(id, wait) do
    lock = path(id)
    File.mkdir_p!(Path.dirname(lock))

    case File.mkdir(lock) do
      :ok ->
        File.write!(Path.join(lock, "by"), "#{System.pid()} #{:erlang.pid_to_list(self())}")
        :ok

      {:error, :eexist} ->
        cond do
          gone?(lock) ->
            File.rm_rf(lock)
            take(id, wait)

          wait == 0 ->
            :busy

          true ->
            Process.sleep(10)
            take(id, wait)
        end
    end
  end

  def release(id), do: File.rm_rf(path(id))

  defp path(id), do: Path.join([Litestream.replica_root(), ".locks", id])

  defp gone?(lock) do
    with {:ok, by} <- File.read(Path.join(lock, "by")),
         [os, erl] <- String.split(by, " ", parts: 2) do
      if os == System.pid(),
        do: not Process.alive?(:erlang.list_to_pid(String.to_charlist(erl))),
        else: not match?({_, 0}, System.cmd("kill", ["-0", os], stderr_to_stdout: true))
    else
      # made and not yet signed: its holder is writing it
      _ -> false
    end
  end
end

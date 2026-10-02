defmodule Moss.Mail.Letter do
  @moduledoc """
  A letter in org (Arock's feature file-kinds, PROJECT.md §18): one org entry, its headline the subject, with
  `FROM`, `TO` and `ID` stamped by the post (`ID` is its own address, `org:<sender>/mail/<n>`). A body with no
  headline becomes the message under one made of the subject. A task is a `TODO` headline; a reply names the
  task it answers in `TASK`, its keyword the task's new state.

  The post checks a letter against the whole node: each `org:` link must name something here (`Moss.Names`), and
  a reply must answer a task its recipient sent its sender. alog reads the org and rockmail judges it
  (`arock.mail` in `priv/lua/host.lua`).
  """

  @doc """
  The letter as the post keeps it: `{:ok, %{"text", "subject", "kind", "task", "links"}}`, or `{:refused, why}`
  for one that is not one org entry or links to nothing. Called outside the post's process: resolving a mail
  address asks the post.
  """
  def read(sender, recipient, subject, body) do
    letter = call(["letter", sender, recipient, subject, body]) |> Jason.decode!()

    with nil <- letter["why"],
         nil <- Enum.find_value(list(letter["links"]), &unresolved/1) do
      {:ok, Map.update(letter, "links", [], &list/1)}
    else
      why -> {:refused, why}
    end
  end

  defp unresolved(address) do
    case Moss.Names.resolve(address) do
      {:ok, _} -> nil
      {:error, why} -> "the letter links to #{address}, and #{why}"
    end
  end

  @doc "`:ok`, or why a reply from `sender` to `recipient` answers no task; `named` is the letter its TASK names, or nil."
  def reply(%{"kind" => "reply", "task" => task}, sender, recipient, named) do
    named = named && Map.take(named, ~w(sender recipient body))

    case Moss.Lua.call("mail", ["reply", task, sender, recipient, named], %{}) do
      {:ok, [nil | _]} -> :ok
      {:ok, []} -> :ok
      {:ok, [why | _]} -> {:refused, why}
    end
  end

  def reply(_letter, _sender, _recipient, _named), do: :ok

  @doc "The number of the letter a TASK address names, when it is a letter's address."
  def task_number(%{"kind" => "reply", "task" => task}) do
    with [_, n] <- Regex.run(~r"\Aorg:[a-z0-9][a-z0-9-]*/mail/(\d+)\z", task),
         do: String.to_integer(n),
         else: (_ -> nil)
  end

  def task_number(_), do: nil

  @doc "The letter with its own address stamped as :ID:."
  def stamp(text, sender, id), do: call(["stamp", text, "org:#{sender}/mail/#{id}"])

  @doc "`mail board`: every task `me` sent or was sent, with its state now, as org."
  def board(letters, me) do
    letters = Enum.map(letters, &Map.take(&1, ~w(id sender recipient body)))
    call(["board", letters, me])
  end

  defp call(args) do
    {:ok, [out | _]} = Moss.Lua.call("mail", args, %{})
    out
  end

  # alog's JSON writes an empty list as {}
  defp list(l) when is_list(l), do: l
  defp list(_), do: []
end

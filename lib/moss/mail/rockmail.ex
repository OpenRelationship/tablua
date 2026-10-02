defmodule Moss.Mail.Rockmail do
  @moduledoc """
  The post's rules from arock-mail (Arock's `submodules/arock-mail`, PROJECT.md
  §18), run in the core's Lua state (`arock.mail` in `priv/lua/host.lua`).
  arock-mail is pure: this host gathers the facts from `Mail.Store`, arock-mail
  decides, and `Moss.Mail` stores and delivers.

    * `check(letter, facts, opts)`: `{:ok, mode}` or `{:refused, reason}`;
    * `ask(letters, history)`: `{state, questions}` for Jev;
    * `verdicts([{letter, answer}], sure)`: what to do with each letter, as
      `%{"state" => _, "verdict" => _}` with `"reason"` and `"flag"` when set.

  Letters and answers go in as maps with string keys and come back the same
  way; no text becomes an atom. The Lua state is config `mail_lua` when set
  (a base built with `Moss.Lua.build/2`), the core's own otherwise.
  """
  alias Moss.Lua

  # what arock-mail reads of a letter
  @fields ~w(id sender recipient subject body state mode read)

  def check(letter, facts, opts) do
    case call("check", [letter, facts, opts]) do
      ["ok", mode] -> {:ok, mode}
      ["refused", reason] -> {:refused, reason}
    end
  end

  def ask(letters, history) do
    [state, questions] = call("ask", [Enum.map(letters, &Map.take(&1, @fields)), history])
    {state, map(questions)}
  end

  def verdicts([], _sure), do: []

  def verdicts(pairs, sure) do
    items =
      Enum.map(pairs, fn {l, answer} ->
        %{"letter" => Map.take(l, @fields), "answer" => answer}
      end)

    [verdicts] = call("verdicts", [items, sure])
    verdicts |> Lua.list() |> Enum.map(&map/1)
  end

  defp call(what, args) do
    case Lua.call("mail", [what | args], %{}, base: Application.get_env(:moss, :mail_lua)) do
      {:ok, results} -> results
      {:error, why} -> raise "rockmail #{what}: #{why}"
    end
  end

  # a decoded Lua table ({key, value} pairs, nested) as a map
  defp map(pairs) when is_list(pairs), do: Map.new(pairs, fn {k, v} -> {k, map(v)} end)
  defp map(v), do: v
end

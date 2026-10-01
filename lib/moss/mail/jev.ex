defmodule Moss.Mail.Jev do
  @moduledoc """
  Jev for the post: `decide(state, questions)` through the core's own port
  (`arock.decide` in `priv/lua/host.lua`), so the host asks Jev exactly as the
  core does. Gives `{:ok, %{question_id => %{"choice" => _, "confidence" => _}}}`
  or `{:error, message}`.
  """
  alias Moss.Lua

  def decide(state, questions) do
    case Lua.call("decide", [state, questions], %{}) do
      {:ok, [answers | _]} -> {:ok, Map.new(answers, fn {id, a} -> {id, Map.new(a)} end)}
      {:error, why} -> {:error, why}
    end
  end
end

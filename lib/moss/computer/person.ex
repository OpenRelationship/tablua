defmodule Moss.Computer.Person do
  @moduledoc """
  What only the person says on a computer (Arock's feature `manifest`): a yes to one request a tool's manifest
  makes (`Grant Reach`), taking it back (`Revoke Reach`), and the answer to a tool marked ASK (`Outcome`, then
  the tool runs). Each is an event on the log by `user`; no command an agent types reaches here.
  """
  alias Moss.Computer.{Manifest, Tools}
  alias Moss.Log

  @doc "Grants `tool` the request `{reach, value}` it asks for: `:ok` or `{:error, why}`."
  def grant(state, tool, reach, value), do: said(state, "Grant Reach", tool, reach, value)

  @doc "Takes back a grant: `:ok` or `{:error, why}`."
  def revoke(state, tool, reach, value), do: said(state, "Revoke Reach", tool, reach, value)

  @doc """
  The person's answer to `line` (a tool's run that asked): logged as an Outcome; a yes runs it.
  `{:ok, %{code, out, err}}` for a yes, `{:ok, nil}` for a no, or `{:error, why}`.
  """
  def answer(state, line, yes?) do
    [name | args] = String.split(line, " ", trim: true)

    case Tools.find(state, name) do
      nil ->
        {:error, "no tool #{name} on this computer"}

      tool ->
        outcome = if yes?, do: "yes", else: "no"

        :ok =
          Log.append(
            state.disk.conn,
            state.id,
            "Outcome",
            [line, outcome, "the person", ""],
            "user"
          )

        if yes? do
          {code, out, err, _} = Tools.run(tool, args, "", state, asked: true)
          {:ok, %{code: code, out: out, err: err}}
        else
          {:ok, nil}
        end
    end
  end

  defp said(state, keyword, name, reach, value) do
    case Manifest.tool(state.disk, name) do
      nil ->
        {:error, "no tool #{name} on this computer"}

      tool ->
        if {reach, value} in Manifest.requests(tool),
          do: Log.append(state.disk.conn, state.id, keyword, [name, reach, value], "user"),
          else: {:error, "#{name} does not ask for #{reach} #{value} in its manifest"}
    end
  end
end

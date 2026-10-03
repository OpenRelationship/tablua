defmodule Moss.Computer.Person do
  @moduledoc """
  What only the person says on a computer (Arock's feature `manifest`): what they write (a writ, and what it made,
  Arock feature notes), a yes to one request a tool's manifest
  makes (`Grant Reach`), taking it back (`Revoke Reach`), and the answer to a tool marked ASK (`Outcome`, then
  the tool runs), agreeing to a feature (`Agree Feature`) and saying yes to a publish. Each is an event on the log by `user`; no command an agent types reaches here.
  """
  alias Moss.Computer.{Board, Loop, Manifest, Tools}
  alias Moss.Log

  @doc """
  The person writes `text` at `path` (from /home): their writ in /home/writs, or what a writ made (Arock feature
  notes). A manifest is checked as an agent's is, a GRANTED line included (the yes is a grant, never a line), and
  once written its tools and triggers are the node's and a request it no longer makes takes its grant back.
  `:ok` or `{:error, why}`.
  """
  def write(state, path, text) do
    path = Moss.Computer.Disk.norm(path, "/home")
    disk = %{state.disk | actor: "user"}
    manifest? = Path.basename(path) == "manifest.org"

    with :ok <- checked(manifest?, text),
         :ok <- Moss.Computer.Disk.write(disk, path, text) do
      if manifest? do
        Moss.Host.manifest(state.id, path, text)
        Manifest.revoke_dropped(disk, state.id)
      end

      :ok
    else
      {:error, why} when is_binary(why) -> {:error, why}
      {:error, why} -> {:error, "#{Moss.Computer.Board.rel(path)}: #{inspect(why)}"}
    end
  end

  defp checked(false, _text), do: :ok

  defp checked(true, text) do
    case Manifest.check(text) do
      [] -> :ok
      errs -> {:error, "manifest.org is refused:\n" <> Enum.join(errs, "\n")}
    end
  end

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

    case if(name == "publish", do: :publish, else: Tools.find(state, name)) do
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
          {code, out, err, _} =
            if tool == :publish,
              do: Loop.publish(Loop.scope(args, state), state, asked: true),
              else: Tools.run(tool, args, "", state, asked: true)

          {:ok, %{code: code, out: out, err: err}}
        else
          {:ok, nil}
        end
    end
  end

  @doc "The person agrees to a feature's scenarios as they stand (`Agree Feature`): `:ok` or `{:error, why}`."
  def agree(state, path) do
    path = Moss.Computer.Disk.norm(path, "/home")

    if String.ends_with?(path, ".feature") and
         match?({:ok, _}, Moss.Computer.Disk.read(state.disk, path)),
       do:
         Log.append(
           state.disk.conn,
           state.id,
           "Agree Feature",
           [path, Board.text_digest(state.disk, path)],
           "user"
         ),
       else: {:error, "no feature #{path}"}
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

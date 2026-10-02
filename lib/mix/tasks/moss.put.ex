defmodule Mix.Tasks.Moss.Put do
  @shortdoc "Puts a folder's files onto a computer's /home"
  @moduledoc """
  Puts every file under a folder onto a computer, at the same paths under
  /home, as the exec port would; with `--owner`, gives the computer to that
  person (otherwise the first person to open it claims it). Used to seed
  Shroomi's gallery:

      mix moss.put shroomi-gallery ../shroomi/examples --as code/examples --app app.lua

  `--as` puts the folder under /home/<as>; `--app <file>` also copies that
  file of it to /home/app.lua, the computer's app.
  """
  use Mix.Task

  @impl true
  def run(argv) do
    {opts, [id, dir], _} =
      OptionParser.parse(argv, strict: [owner: :string, as: :string, app: :string])

    # the node beside this task, if one runs, streams the work dir: this BEAM starts no Litestream of its own
    Mix.Task.run("app.config")
    Application.put_env(:moss, :litestream_run, false)
    Mix.Task.run("app.start")
    root = Path.expand(dir)
    under = opts[:as] || ""

    files =
      for f <- Path.wildcard(Path.join(root, "**/*")), File.regular?(f), into: %{} do
        {Path.join(under, Path.relative_to(f, root)), File.read!(f)}
      end

    files =
      if app = opts[:app],
        do: Map.put(files, "app.lua", File.read!(Path.join(root, app))),
        else: files

    r = Moss.Computer.exec(id, %{"cwd" => "/home", "cmd" => "ls", "files" => files})
    if r["code"] != 0, do: Mix.raise(r["stderr"])
    if owner = opts[:owner], do: :ok = Moss.Owners.claim(id, owner)
    :ok = Moss.Computer.sleep(id)

    Mix.shell().info(
      "#{map_size(files)} files on #{id}: #{String.trim(r["stdout"]) |> String.replace("\n", " ")}"
    )
  end
end

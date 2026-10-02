defmodule Moss.Computer.Kinds do
  @moduledoc """
  What an agent may write under `/home` (Arock's feature `file-kinds`): six kinds of file in six folders, each
  with one job the computer does for it, at `/home` for the computer's own work and at `/home/apps/<app>/` for
  each app, laid out the same way.

      features/*.feature   the spec and the test       code/*.lua    the work
      ui/*.lui             pages                       data/*.dbl    databases (db.open), never a file's bytes
      org/*.org            tasks, notes, plans         files/**      every other format, data and binary
      manifest.org         what the computer or app offers (feature manifest)

  A write anywhere else is refused with the folder it belongs in. `/tmp` is scratch and free. `/home/app.lua` is
  served until the gallery moves to apps (feature file-kinds, goal 10), and goes with it.
  """

  @folders ~w(features code ui data org files)
  @ext %{".feature" => "features", ".lua" => "code", ".lui" => "ui", ".org" => "org", ".dbl" => "data"}
  @what %{
    "features" => "a feature goes in features/ as .feature",
    "code" => "code goes in code/ as .lua",
    "ui" => "a page goes in ui/ as .lui",
    "org" => "an org file goes in org/ as .org",
    "data" => "a database goes in data/ as .dbl, opened with db.open"
  }
  @app ~r"\A[a-z0-9][a-z0-9-]{0,63}\z"

  def folders, do: @folders

  @doc "`:ok` when a file may be written at absolute `path`, or `{:error, why}`."
  def file(path) do
    case where(path) do
      :free -> :ok
      {:bad_app, app} -> {:error, bad_app(app)}
      {:root, "app.lua"} -> :ok
      {_scope, "manifest.org"} -> :ok
      {_scope, [folder | rest]} -> in_folder(folder, rest, path)
      {:apps, _} -> {:error, "apps/ holds apps, each a folder with the same six"}
      {_scope, name} when is_binary(name) -> {:error, outside(name)}
    end
  end

  @doc "`:ok` when a folder may be made at `path`: a kind folder, anything inside one, or an app."
  def folder(path) do
    case where(path) do
      :free -> :ok
      {:bad_app, app} -> {:error, bad_app(app)}
      {_scope, folder} when folder in @folders -> :ok
      {_scope, [folder | _]} when folder in @folders -> :ok
      {:apps, nil} -> :ok
      {:apps, app} -> if Regex.match?(@app, app), do: :ok, else: {:error, bad_app(app)}
      {_scope, name} when is_binary(name) -> {:error, outside_folder(name)}
      {_scope, [name | _]} -> {:error, outside_folder(name)}
    end
  end

  @doc "`:ok` when a database may be named `path` (db.open): data/*.dbl at /home or in an app."
  def database(path) do
    case where(path) do
      :free -> :ok
      {_scope, ["data" | rest]} when rest != [] -> if Path.extname(path) == ".dbl", do: :ok, else: {:error, @what["data"]}
      _ -> {:error, @what["data"] <> ": db.open(\"data/#{Path.rootname(Path.basename(path))}.dbl\")"}
    end
  end

  # :free outside /home; {scope, name} for a file right in a scope; {scope, [folder | rest]} inside one;
  # {:apps, nil} for /home/apps, {:apps, name} for what sits right in it
  defp where(path) do
    case Path.split(path) do
      ["/", "home" | rest] -> scoped(rest)
      _ -> :free
    end
  end

  defp scoped([]), do: :free
  defp scoped(["apps"]), do: {:apps, nil}

  defp scoped(["apps", app]), do: {:apps, app}

  defp scoped(["apps", app | rest]) do
    if Regex.match?(@app, app), do: in_scope({:app, app}, rest), else: {:bad_app, app}
  end

  defp scoped(rest), do: in_scope(:root, rest)

  defp in_scope(scope, [name]), do: {scope, name}
  defp in_scope(scope, parts), do: {scope, parts}

  defp in_folder("files", _rest, _path), do: :ok
  defp in_folder("data", _rest, _path), do: {:error, @what["data"] <> "; a file\x27s bytes never become one"}

  defp in_folder(folder, rest, path) when folder in @folders do
    want = @ext[Path.extname(path)]

    cond do
      rest == [] -> {:error, "#{folder}/ is a folder"}
      want == folder -> :ok
      want == nil -> {:error, "#{folder}/ holds #{kind(folder)}; #{Path.basename(path)} goes in files/"}
      true -> {:error, "#{@what[folder]}; #{Path.basename(path)} is #{kind(want)} and goes in #{want}/"}
    end
  end

  defp in_folder(_folder, _rest, path), do: {:error, outside(path)}

  defp kind("features"), do: "features"
  defp kind("code"), do: "code"
  defp kind("ui"), do: "pages"
  defp kind("org"), do: "org files"
  defp kind("data"), do: "databases"

  defp outside(name) do
    folder = @ext[Path.extname(name)] || "files"

    "a file on this computer goes in one of features/, code/, ui/, data/, org/ or files/ " <>
      "(at /home, or in apps/<app>/ the same); #{Path.basename(name)} belongs in #{folder}/"
  end

  defp outside_folder(name),
    do: "folders under /home are features/, code/, ui/, data/, org/, files/ and apps/<app>/, not #{name}/"

  defp bad_app(app), do: "an app\x27s name is a-z, 0-9 and -, at most 64, not #{app}"
end

defmodule Moss.Computer.Pages do
  @moduledoc """
  Which page answers a request (Arock's feature `file-kinds`): a page is served at its path in its app, an `.org`
  page (org and Lua, arock issue #2) before a `.lui` one of the same name. `/plants/list` is
  `apps/plants/ui/list.org` (or `.lui`) when the computer has an app `plants`, and `/list` is `/home/ui/list.org`;
  a path ending at a folder is its `index`. A part (`ui/_row.lui`) is never served.
  The page runs in its app's folder, so `data/plants.dbl` is the app's own. An app is served only when the root
  manifest lists it (feature manifest): a folder under apps/ not listed is not found.
  """
  alias Moss.Computer.{Disk, Manifest}

  @doc "`{cwd, page}`: the folder a request runs in and its page's path, or `{\"/home\", nil}` for none."
  def route(path, disk) do
    parts = String.split(path, "/", trim: true)

    {root, rest} =
      case parts do
        [app | rest] ->
          if app?(disk, app), do: {"/home/apps/" <> app, rest}, else: {"/home", parts}

        [] ->
          {"/home", []}
      end

    case page(root, rest, String.ends_with?(path, "/")) do
      nil ->
        {"/home", nil}

      base ->
        case Enum.find([base <> ".org", base <> ".lui"], &file?(disk, &1)) do
          nil -> {"/home", nil}
          file -> {root, file}
        end
    end
  end

  @doc """
  The request as its page sees it, the folder it runs in, and the app it is in (nil for the computer's own):
  `req` gains `page`, and its path is from the app's root.
  """
  def request(req, disk) do
    case route(req["path"], disk) do
      {cwd, nil} ->
        {req, cwd, nil}

      {cwd, page} ->
        app = app(cwd)
        {Map.merge(req, %{"page" => page, "path" => local_path(req["path"], app)}), cwd, app}
    end
  end

  @doc "An app's answer, marked so its page gets its <base> at the app (`Moss.Computer.App`)."
  def from_app(answer, nil), do: answer
  def from_app({s, h, b, e}, app), do: {s, Map.put(h, "x-moss-app", app), b, e}

  @doc "The app a page of `cwd` belongs to, or nil for the computer's own."
  def app("/home/apps/" <> name), do: name
  def app(_cwd), do: nil

  @doc "The path as the page sees it: from its app's root (`/plants/list` is `/list` in the app plants)."
  def local_path(path, nil), do: path

  def local_path(path, app) do
    case String.split(path, "/", trim: true) do
      [^app | rest] ->
        folder = if rest != [] and String.ends_with?(path, "/"), do: "/", else: ""
        "/" <> Enum.join(rest, "/") <> folder

      _ ->
        path
    end
  end

  defp app?(disk, name),
    do:
      Regex.match?(~r"\A[a-z0-9][a-z0-9-]{0,63}\z", name) and
        match?({:ok, %{dir: true}}, Disk.stat(disk, "/home/apps/" <> name)) and
        Manifest.listed?(disk, name)

  defp page(root, rest, folder?) do
    cond do
      Enum.any?(rest, &(String.starts_with?(&1, "_") or String.starts_with?(&1, "."))) -> nil
      rest == [] or folder? -> Path.join([root, "ui" | rest] ++ ["index"])
      true -> Path.join([root, "ui" | rest])
    end
  end

  defp file?(disk, file), do: match?({:ok, %{dir: false}}, Disk.stat(disk, file))
end

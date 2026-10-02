defmodule Moss.Computer.Look do
  @moduledoc """
  The computer's own app read as its person's browser lays it out (Arock feature look): moss-browser's look
  (`Moonflower.Look`, Blitz in WebAssembly, in a node of its own) is given the page and Shroomi's pinned stylesheet,
  at the browser's screen (`open app --width N --dark`), and only what it shows is read.

  The module is moss-browser's release, fetched by `mix moss.look` and checked by its SHA-384 (config `:look`);
  the node runs `Moonflower.Look.Node` only when the file is there and matches. Without it, or when a look fails,
  the page is read as it would be without one, and a page too costly to lay out says so.
  """
  require Logger
  alias Moonflower.Page

  @screen %{width: 1280, dark: false}
  def screen, do: @screen

  @doc "The look node's child spec, or none when the module is missing or is not the pinned one."
  def children do
    with %{path: path, sha384: sha} <- Map.new(Application.get_env(:moss, :look, [])),
         {:ok, bytes} <- File.read(path) do
      if hash(bytes) == sha do
        [{Moonflower.Look.Node, path: path, sha384: sha}]
      else
        Logger.warning("look: #{path} is not the pinned module; apps are read without a look")
        []
      end
    else
      _ -> []
    end
  end

  defp hash(bytes), do: :crypto.hash(:sha384, bytes) |> Base.encode16(case: :lower)

  @doc "The page at `url`, laid out at `screen` when the look node runs."
  def page(url, html, notes, screen) do
    with pid when is_pid(pid) <- Process.whereis(Moonflower.Look.Node),
         {:ok, look} <-
           Moonflower.Look.look(Moonflower.Look.Node, html,
             width: screen.width,
             dark: screen.dark,
             base: url,
             css: css()
           ) do
      Page.looked(url, look, notes)
    else
      {:error, :too_costly} ->
        Page.new(url, html, notes ++ ["(too costly to lay out; read without a look)"])

      _ ->
        Page.new(url, html, notes)
    end
  end

  # Shroomi's stylesheet, the one an app's page links (Clean.policy's css), read once from its pinned asset
  defp css do
    case :persistent_term.get({__MODULE__, :css}, nil) do
      nil ->
        "/shroomi/" <> file = Moss.Computer.Clean.policy().css
        dir = Path.join(Moss.Lua.Sources.core(), "submodules/shroomi/assets")
        css = File.read!(Path.join(dir, file))
        :persistent_term.put({__MODULE__, :css}, css)
        css

      css ->
        css
    end
  end

  @doc "`open app`'s flags, `--width N` and `--dark` (or `--light`), over the screen the browser has."
  def flags([], screen), do: {:ok, screen}
  def flags(["--dark" | rest], s), do: flags(rest, %{s | dark: true})
  def flags(["--light" | rest], s), do: flags(rest, %{s | dark: false})

  def flags(["--width", n | rest], s) do
    case Integer.parse(n) do
      {w, ""} when w in 320..3840 -> flags(rest, %{s | width: w})
      _ -> {:error, "open: --width #{n}: a width from 320 to 3840"}
    end
  end

  def flags([other | _], _s),
    do: {:error, "open: #{other}: --width N (320 to 3840), --dark or --light"}
end

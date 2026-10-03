defmodule Moss.Computer.Help do
  @moduledoc """
  `help` on the computer (Arock's feature file-kinds, "Mercury's context"): a short index, then one topic per kind
  of file and per part of the computer, each short enough to sit in a model's context beside the work. Each topic
  is read from the files that do the work (their opening comments), so what help says is what they do.
  """
  alias Moss.Computer.{App, Browser, Loop, Mailbox, Script, Tools}

  @index """
  Your computer. Six kinds of file, each in its own folder, at /home and in each app (apps/<name>/):

    features/*.feature   the spec and the test           help feature
    code/*.lua           the work, in Lua                help code    (help lua <module>: one module)
    ui/*.lui             pages: HTML with Lua in it      help page    (help kit, help classes)
    data/*.dbl           databases                       help data
    org/*.org            tasks, notes, plans             help org     (help org task|note|letter|manifest)
    files/**             every other format              help files
    manifest.org         apps, tools, triggers, reach    help manifest

  How you work: help loop (new, test, check, status, publish). Your procedures are org/procedures/*.org.
  The post: help mail. Your browser: help open. A write in the wrong place is refused with where it goes.
  """

  @data """
  Databases: data/<name>.dbl, opened by name from Lua; a file's bytes never become one.

    local d = db.open("data/plants.dbl")      -- the working folder's data/, so an app's own in an app
    d:exec("create table if not exists plant (name text primary key, watered text)")
    d:exec("insert into plant values (?, ?)", "Fern", nil)
    for _, p in ipairs(d:query("select * from plant order by name")) do print(p.name) end
    local one = d:one("select count(*) as n from plant")   -- one.n

  SQLite's SQL: create table/index, alter table add column, drop; insert (or ignore/replace, on conflict, returning);
  select with joins, group by, subqueries, union; update; delete; begin/commit/rollback. ? and :name bind the
  arguments after the SQL. Views, triggers, WITH, window functions and pragma are refused. 64 MB at most.
  ls shows a database, cat sums it up, rm removes it. A bad statement stops the code that ran it with its file,
  line and why (pcall it to go on); db.open returns nil and why.
  """

  @files """
  files/: every other format, data and binary alike (a CSV, a PDF, an image, a downloaded page). Read and written
  with fs.read and fs.write, never run. csv, json and date read them in Lua: csv.parse(s), json.decode(s).
  Anything that is a kind of its own goes in its folder instead: .lua in code/, .lui in ui/, .org in org/.
  """

  @topics ~w(feature code page kit classes data org files manifest tools loop new test check status publish mail)

  def topics, do: @topics

  @doc "The text for `help [topic ...]`."
  def run([]), do: @index <> "\ncommands: " <> Enum.join(Moss.Computer.Commands.names(), " ") <> "\n"
  def run(["feature" | _]), do: module("test") <> "\nSteps live in code/steps/*.lua; `test` prints a stub for each one missing.\n"
  def run(["code" | _]), do: Script.prelude_help() <> "\n" <> modules()
  def run(["lua", name | _]), do: module(name)
  def run(["lua" | _]), do: modules()
  def run(["page" | _]), do: module("shroomi.lui") <> App.help()
  def run(["kit" | _]), do: module("shroomi.components")
  def run(["classes" | _]), do: module("shroomi.css")
  def run(["data" | _]), do: @data
  def run(["files" | _]), do: @files
  def run(["org" | rest]), do: org(rest)
  def run([m | _]) when m in ~w(manifest tools), do: Tools.help()
  def run([m | _]) when m in ~w(loop new test check status publish), do: Loop.help()
  def run(["mail" | _]), do: Mailbox.help()
  def run(_browser), do: Browser.help()

  @doc "Whether `help <topic>` has a topic of its own (the browser's commands are Browser's)."
  def topic?(name), do: name in @topics or name == "lua"

  defp module(name) do
    case Script.module_help(name) do
      nil -> "help: no module #{name}\n" <> modules()
      text -> text
    end
  end

  # each module of the library with the first line it says about itself
  defp modules do
    lines =
      for {name, first} <- Script.module_index(),
          do: "  #{String.pad_trailing(name, 20)} #{first}\n"

    "The library's modules (require(name); date, csv and test are at hand), help lua <module> for one:\n" <>
      Enum.join(lines)
  end

  defp org([]), do: org_help(nil)
  defp org([kind | _]), do: org_help(kind)

  defp org_help(kind) do
    case Moss.Lua.call("names", ["help", kind], %{}) do
      {:ok, [text | _]} -> text
      {:error, _} -> "help org: the kinds are task, note, letter and manifest\n"
    end
  end
end

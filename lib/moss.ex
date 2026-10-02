defmodule Moss do
  @moduledoc """
  MOSS, the agent's own computer (Arock PROJECT.md §14): a process per agent (`Moss.Computer`), its disk one SQLite
  file, a shell of its own, a browser, mail at its host's post, and Lua run on moss-lua with the computer as its
  library. A host runs it (`Moss.Host`): arock-server on a node, or `Moss.Host.Local` on its own.
  """
end

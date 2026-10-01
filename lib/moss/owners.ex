defmodule Moss.Owners do
  @moduledoc """
  Whose each computer is: a person's account owns it, first come. The pages
  show a person only their computers and the post only what touches them
  (Arock PROJECT.md §14.7). One process per node holds the claims in the
  node's `owners.sqlite`.

      Owners.claim("rock-7", "sam")   # :ok, or {:error, :taken} when it is someone else's
      Owners.owner("rock-7")          # "sam", or nil
      Owners.mine("rock-7", "sam")    # true
      Owners.owned("sam")             # ["rock-7"]
  """
  use GenServer
  alias Moss.Db

  def claim(id, person), do: GenServer.call(__MODULE__, {:claim, id, person})
  def owner(id), do: GenServer.call(__MODULE__, {:owner, id})
  def owned(person), do: GenServer.call(__MODULE__, {:owned, person})
  def mine(id, person), do: person != nil and owner(id) == person

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(opts) do
    path = opts[:path] || Path.join(Application.fetch_env!(:moss, :work_dir), "owners.sqlite")
    File.mkdir_p!(Path.dirname(path))
    {:ok, conn} = Db.open(path)

    {:ok, _} =
      Db.exec(
        conn,
        "create table if not exists owners (computer text primary key, person text not null, at integer not null)",
        []
      )

    {:ok, conn}
  end

  @impl true
  def handle_call({:claim, id, person}, _from, conn) do
    {:ok, _} =
      Db.exec(conn, "insert or ignore into owners (computer, person, at) values (?1, ?2, ?3)", [
        id,
        person,
        System.os_time(:second)
      ])

    {:reply, if(owner_of(conn, id) == person, do: :ok, else: {:error, :taken}), conn}
  end

  def handle_call({:owner, id}, _from, conn), do: {:reply, owner_of(conn, id), conn}

  def handle_call({:owned, person}, _from, conn) do
    {:ok, rows} =
      Db.exec(conn, "select computer from owners where person = ?1 order by computer", [person])

    {:reply, Enum.map(rows, & &1["computer"]), conn}
  end

  defp owner_of(conn, id) do
    case Db.exec(conn, "select person from owners where computer = ?1", [id]) do
      {:ok, [%{"person" => p}]} -> p
      _ -> nil
    end
  end
end

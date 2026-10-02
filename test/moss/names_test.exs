defmodule Moss.NamesTest do
  # Arock's feature manifest: every computer, app, tool, entry and letter has one org: address, resolved by the
  # node from the manifests computers write (their zone files), without waking them; org: is never the web.
  use ExUnit.Case, async: false

  alias Moss.{Computer, Mail, Names}
  alias Moss.Computer.Net

  defp id, do: "names-#{System.unique_integer([:positive])}"

  defp write(c, files), do: :ok = GenServer.call(Computer.wake!(c), {:files, "/home", files})

  @root """
  #+TITLE: fern

  * Apps
  - [[org:FERN/plants]]

  * Tools
  ** weather
  :PROPERTIES:
  :RUN: code/weather.lua
  :NET: api.open-meteo.com
  :END:
  Pull the day's weather.
  - city :: string
  """

  defp root(c), do: String.replace(@root, "FERN", c)

  @seed """
  * Tools
  ** seed
  :PROPERTIES:
  :RUN: code/seed.lua
  :END:
  Fill the plants database.
  """

  test "a computer, its apps and its tools resolve from its manifests" do
    c = id()
    write(c, [{"manifest.org", root(c)}, {"apps/plants/manifest.org", @seed}])
    assert Names.resolve("org:" <> c) == {:ok, "computer"}
    assert Names.resolve("org:#{c}/plants") == {:ok, "app"}
    assert Names.resolve("org:#{c}/weather") == {:ok, "tool"}
    assert Names.resolve("org:#{c}/plants/seed") == {:ok, "tool"}
  end

  test "an address to nothing is refused, and a bad one says why" do
    c = id()
    write(c, [{"manifest.org", root(c)}])
    assert {:error, "the address org:" <> rest} = Names.resolve("org:#{c}/no-such-tool")
    assert rest =~ "names nothing on this node"
    assert {:error, "an address" <> _} = Names.resolve("org:Fern/plants")
    assert {:error, _} = Names.resolve("https://fern.org/")
  end

  test "a manifest rewritten, removed or moved changes what it names" do
    c = id()
    write(c, [{"manifest.org", root(c)}, {"apps/plants/manifest.org", @seed}])
    write(c, [{"manifest.org", String.replace(root(c), "** weather", "** forecast")}])
    assert {:error, _} = Names.resolve("org:#{c}/weather")
    assert Names.resolve("org:#{c}/forecast") == {:ok, "tool"}

    assert %{code: 0} = Computer.run(c, "mv apps/plants apps/garden")
    assert {:error, _} = Names.resolve("org:#{c}/plants/seed")
    assert Names.resolve("org:#{c}/garden/seed") == {:ok, "tool"}

    assert %{code: 0} = Computer.run(c, "rm manifest.org")
    assert {:error, _} = Names.resolve("org:#{c}/plants")
    assert Names.resolve("org:" <> c) == {:ok, "computer"}
  end

  test "entries and letters have addresses" do
    [a, b] = [id(), id()]
    Computer.wake!(a)
    Computer.wake!(b)
    :ok = Names.entry(a, "e12")
    assert Names.resolve("org:#{a}/entries/e12") == {:ok, "entry"}
    assert {:error, _} = Names.resolve("org:#{a}/entries/e13")

    :ok = Mail.route(a, b, "audit")
    assert {:delivered, n} = Mail.post(a, b, "fern", "the fern needs water")
    assert Names.resolve("org:#{a}/mail/#{n}") == {:ok, "letter"}
    assert Names.resolve("org:#{b}/mail/#{n}") == {:ok, "letter"}
    assert {:error, _} = Names.resolve("org:#{id()}/mail/#{n}")
  end

  test "an app or tool may not take a reserved part's name" do
    c = id()
    write(c, [{"manifest.org", "* Apps\n- [[org:#{c}/mail]]\n"}])
    assert {:error, _} = Names.resolve("org:#{c}/mail")
  end

  test "fern.org stays the web: a computer named fern changes nothing about https://fern.org/" do
    write("fern", [{"manifest.org", root("fern")}])
    test = self()

    Req.Test.stub(Net, fn conn ->
      send(test, {:web, Plug.Conn.get_req_header(conn, "host")})
      Plug.Conn.send_resp(conn, 200, "someone else's website")
    end)

    c = Computer.wake!("fern")
    Req.Test.allow(Net, self(), c)

    old = Application.get_env(:moss, :resolver)
    Application.put_env(:moss, :resolver, fn _ -> [{93, 184, 215, 14}] end)

    try do
      assert %{code: 0, out: "someone else's website"} = Computer.run("fern", "curl https://fern.org/")
    after
      if old, do: Application.put_env(:moss, :resolver, old), else: Application.delete_env(:moss, :resolver)
    end

    assert_received {:web, ["fern.org"]}
  end
end

defmodule Moss.ManifestTest do
  # Arock's feature manifest, bdd/manifest.feature: a computer's manifest.org lists its apps and its agent's tools,
  # each with typed arguments, triggers and the reach it asks for; only the person grants reach, each grant an
  # event on the log, checked at every call. (Addresses are Moss.NamesTest's.)
  use ExUnit.Case, async: false

  alias Moss.{Computer, Triggers}
  alias Moss.Computer.{Disk, Net}

  defp id, do: "manifest-#{System.unique_integer([:positive])}"
  defp sh(c, line), do: Computer.run(c, line)
  defp disk(c), do: :sys.get_state(Computer.wake!(c)).disk
  defp write(c, path, text), do: Disk.write(disk(c), path, text)
  defp get(c, path), do: Computer.serve(c, %{"method" => "GET", "path" => path})

  defp events(c, keywords) do
    {:ok, rows} =
      Moss.Db.exec(
        disk(c).conn,
        "select e.keyword, e.actor, group_concat(a.value, ' | ') as args from events e " <>
          "join args a on a.seq = e.seq where e.keyword in (select value from json_each(?)) " <>
          "group by e.seq order by e.seq",
        [Jason.encode!(keywords)]
      )

    for r <- rows, do: {r["keyword"], r["actor"], r["args"]}
  end

  defp tool(name, props, text \\ "Does its work.") do
    lines = for {k, v} <- props, do: ":#{k}:" <> if(v == true, do: "", else: " " <> v)
    Enum.join(["** " <> name, ":PROPERTIES:" | lines] ++ [":END:", text], "\n") <> "\n"
  end

  defp manifest(c, tools, apps \\ []) do
    links = for a <- apps, do: "- [[org:#{c}/#{a}]]\n"
    :ok = write(c, "/home/manifest.org", "* Apps\n#{links}\n* Tools\n" <> Enum.join(tools))
  end

  @weather ~S"""
  print(arg.city, arg[1], fs.cwd())
  if arg.fetch then print(http.get("http://" .. arg.fetch .. "/now")) end
  if arg.also then print(http.get("http://" .. arg.also .. "/now")) end
  """

  setup do
    c = id()
    :ok = write(c, "/home/code/weather.lua", @weather)
    %{c: c}
  end

  test "Scenario: a tool runs its code", %{c: c} do
    manifest(c, [
      tool("weather", [RUN: "code/weather.lua"], "Pull the day's weather.\n- city :: string")
    ])

    assert %{code: 0, out: "Lisbon\tLisbon\t/home\n"} = sh(c, "weather Lisbon")
  end

  test "Scenario: the tool list carries typed arguments", %{c: c} do
    manifest(c, [
      tool(
        "weather",
        [RUN: "code/weather.lua"],
        "Pull the day's weather.\n- city :: string\n- days :: number = 3"
      )
    ])

    assert %{code: 0, out: out} = sh(c, "tools")
    assert out =~ "weather: Pull the day's weather."
    assert out =~ "  city :: string\n  days :: number\n"
  end

  test "Scenario: an argument of the wrong type is refused", %{c: c} do
    manifest(c, [tool("water", [RUN: "code/weather.lua"], "Water.\n- days :: number")])
    assert %{code: 2, err: err} = sh(c, "water soon")
    assert err =~ "days is a number, and soon is not"
  end

  test "Scenario: an app exists because it is listed", %{c: c} do
    :ok = write(c, "/home/apps/plants/ui/index.lui", "<p>Plants</p>")
    manifest(c, [])
    assert {404, _, _, _} = get(c, "/plants/")
    manifest(c, [], ["plants"])
    assert {200, _, body, _} = get(c, "/plants/")
    assert body =~ "<p>Plants</p>"
  end

  test "Scenario: an app's tools are named under it", %{c: c} do
    :ok = write(c, "/home/apps/plants/code/seed.lua", ~S|print("seeded in " .. fs.cwd())|)

    :ok =
      write(
        c,
        "/home/apps/plants/manifest.org",
        "* Tools\n" <> tool("seed", RUN: "code/seed.lua")
      )

    manifest(c, [], ["plants"])
    assert %{code: 0, out: "seeded in /home/apps/plants\n"} = sh(c, "plants:seed")
  end

  @weather_net "Pull the day's weather.\n- city :: string\n- fetch :: string?\n- also :: string?"

  test "Scenario: writing a request grants nothing", %{c: c} do
    manifest(c, [tool("weather", [RUN: "code/weather.lua", NET: "93.184.215.14"], @weather_net)])
    assert %{code: 0, out: out} = sh(c, "weather Lisbon 93.184.215.14")

    assert out =~
             "nil\tNET 93.184.215.14: weather asks for it, and the person has not said yes yet"

    assert sh(c, "tools").out =~ "NET 93.184.215.14: asked, not granted yet"
  end

  test "Scenario: a granted tool reaches only its host", %{c: c} do
    Req.Test.stub(Net, fn conn -> Plug.Conn.send_resp(conn, 200, "sunny") end)
    Req.Test.allow(Net, self(), Computer.wake!(c))
    manifest(c, [tool("weather", [RUN: "code/weather.lua", NET: "93.184.215.14"], @weather_net)])

    assert {:error, "weather does not ask for NET 93.184.215.15 in its manifest"} =
             Computer.grant(c, "weather", "NET", "93.184.215.15")

    :ok = Computer.grant(c, "weather", "NET", "93.184.215.14")
    assert [{"Grant Reach", "user", "weather | NET | 93.184.215.14"}] = events(c, ["Grant Reach"])

    assert %{code: 0, out: out} = sh(c, "weather Lisbon 93.184.215.14 93.184.215.15")

    assert [_, "table: " <> _, "nil\tNET 93.184.215.15: weather does not ask for it" <> _] =
             String.split(out, "\n", trim: true)

    # a lua run outside a tool reaches nothing, whatever the tools were granted
    assert sh(c, ~s|lua -e 'print(http.get("http://93.184.215.14/now"))'|).out =~
             "outside a tool reaches nothing"
  end

  test "Scenario: an agent cannot grant itself", %{c: c} do
    props = [RUN: "code/weather.lua", NET: "api.open-meteo.com", GRANTED: "2026-10-02"]
    assert {:error, why} = write(c, "/home/manifest.org", "* Tools\n" <> tool("weather", props))
    assert why =~ "manifest.org is refused:\n2: the tool weather: GRANTED is written by the host"
    assert {:error, :enoent} = Disk.read(disk(c), "/home/manifest.org")
  end

  test "Scenario: removing a request takes its grant back", %{c: c} do
    asks = tool("weather", [RUN: "code/weather.lua", NET: "93.184.215.14"], @weather_net)
    manifest(c, [asks])
    :ok = Computer.grant(c, "weather", "NET", "93.184.215.14")
    manifest(c, [tool("weather", [RUN: "code/weather.lua"], @weather_net)])
    manifest(c, [asks])

    assert [{"Grant Reach", "user", _}, {"Revoke Reach", "host", "weather | NET | 93.184.215.14"}] =
             events(c, ["Grant Reach", "Revoke Reach"])

    assert sh(c, "weather Lisbon 93.184.215.14").out =~ "the person has not said yes yet"
  end

  test "Scenario: a tool marked ASK waits for the person", %{c: c} do
    :ok =
      write(
        c,
        "/home/code/summary.lua",
        ~S|fs.write("files/summary.txt", "posted") print("posted")|
      )

    manifest(c, [tool("post-summary", RUN: "code/summary.lua", ASK: true)])

    assert %{code: 3, err: err} = sh(c, "post-summary")
    assert err =~ "waits for the person's yes"
    assert {:error, :enoent} = Disk.read(disk(c), "/home/files/summary.txt")
    assert [{"Ask Person", "agent", "post-summary | post-summary"}] = events(c, ["Ask Person"])

    assert {:ok, nil} = Computer.answer(c, "post-summary", false)
    assert {:ok, %{code: 0, out: "posted\n"}} = Computer.answer(c, "post-summary", true)
    assert {:ok, "posted"} = Disk.read(disk(c), "/home/files/summary.txt")

    assert [
             {"Outcome", "user", "post-summary | no | the person" <> _},
             {"Outcome", "user", "post-summary | yes" <> _}
           ] =
             events(c, ["Outcome"])
  end

  test "Scenario: a trigger wakes a sleeping computer", %{c: c} do
    :ok = write(c, "/home/code/triage.lua", ~S|fs.write("files/triaged.txt", "done")|)
    manifest(c, [tool("triage", RUN: "code/triage.lua", EVERY: "daily 07:00")])
    [%{since: since}] = for t <- Moss.Names.triggers(), t.computer == c, do: t

    :ok = Computer.sleep(c)
    assert Computer.whereis(c) == nil

    seven = Triggers.next_at("daily 07:00", since)
    assert rem(seven, 86_400) == 7 * 3600
    refute Enum.any?(Triggers.tick(seven - 60), &match?({^c, _, _}, &1))
    assert Computer.whereis(c) == nil

    assert {c, "triage", 0} in Triggers.tick(seven)
    assert Computer.whereis(c) != nil
    assert {:ok, "done"} = Disk.read(disk(c), "/home/files/triaged.txt")
    # it ran once for 07:00, and runs again the next day
    refute Enum.any?(Triggers.tick(seven + 60), &match?({^c, _, _}, &1))
    assert {c, "triage", 0} in Triggers.tick(seven + 86_400)
  end

  test "every trigger's next time" do
    mon = DateTime.to_unix(~U[2026-10-05 08:30:00Z])
    assert Triggers.next_at("hourly", mon) == DateTime.to_unix(~U[2026-10-05 09:00:00Z])
    assert Triggers.next_at("every 15m", mon) == mon + 900
    assert Triggers.next_at("every 2d", mon) == mon + 2 * 86_400
    assert Triggers.next_at("daily 07:00", mon) == DateTime.to_unix(~U[2026-10-06 07:00:00Z])
    assert Triggers.next_at("daily 09:15", mon) == DateTime.to_unix(~U[2026-10-05 09:15:00Z])
    assert Triggers.next_at("weekly Mon 07:00", mon) == DateTime.to_unix(~U[2026-10-12 07:00:00Z])
    assert Triggers.next_at("weekly Fri 17:00", mon) == DateTime.to_unix(~U[2026-10-09 17:00:00Z])
  end
end

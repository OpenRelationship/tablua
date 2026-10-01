defmodule VolvoxServerWeb.MacChannelTest do
  # PROJECT.md §13, goal 4: a task that needs the Mac goes to the Mac app when it is online, and
  # otherwise waits while the rock says it is waiting.
  use ExUnit.Case, async: false
  import Phoenix.ChannelTest

  alias VolvoxServer.{Mac, Run}
  alias VolvoxServerWeb.MacSocket

  @endpoint VolvoxServerWeb.Endpoint

  defp id, do: "macrun-#{System.unique_integer([:positive])}"

  defp keywords(run), do: for(e <- Run.snapshot(run).events, do: {e.keyword, e.args})

  # The tests share one owner, so each looks only at its own work.
  defp waits?(work), do: Enum.any?(Mac.waiting("owner1"), &(&1.id == work))

  defp online do
    {:ok, socket} = connect(MacSocket, %{"token" => "test-mac-token"})
    {:ok, _, socket} = subscribe_and_join(socket, "mac:owner1", %{})
    socket
  end

  test "a Mac that is online gets the work at once and its result reaches the run" do
    socket = online()
    run = id()
    {:ok, work} = Mac.need("owner1", run, "t1", "open Notes and read the last note")

    assert_push "work", %{
      id: ^work,
      run: ^run,
      task: "t1",
      request: "open Notes and read the last note"
    }

    ref = push(socket, "done", %{"id" => work, "result" => "Buy milk"})
    assert_reply ref, :ok

    assert {"Sent To Mac", ["open Notes and read the last note"]} in keywords(run)
    assert {"Mac Result", ["open Notes and read the last note", "Buy milk"]} in keywords(run)
    refute waits?(work)
  end

  test "with the Mac offline the work waits, the rock says so, and it goes when the Mac joins" do
    run = id()
    {:ok, work} = Mac.need("owner1", run, "t1", "empty the Downloads folder")
    assert waits?(work)
    assert {"Waiting For Mac", ["empty the Downloads folder"]} in keywords(run)
    assert Enum.any?(keywords(run), fn {k, [said]} -> k == "Say" and said =~ "waits" end)

    _socket = online()
    assert_push "work", %{id: ^work, request: "empty the Downloads folder"}
    Process.sleep(20)
    refute waits?(work)
    assert {"Sent To Mac", ["empty the Downloads folder"]} in keywords(run)
  end

  test "work a Mac had not finished waits again when it goes away" do
    socket = online()
    run = id()
    {:ok, work} = Mac.need("owner1", run, "t1", "rename the screenshot")
    assert_push "work", %{id: ^work}
    Process.unlink(socket.channel_pid)
    ref = Process.monitor(socket.channel_pid)
    close(socket)
    assert_receive {:DOWN, ^ref, _, _, _}
    Process.sleep(20)
    assert waits?(work)
  end

  test "a wrong token or another person's Mac is refused" do
    assert :error = connect(MacSocket, %{"token" => "nope"})
    assert :error = connect(MacSocket, %{})
    {:ok, socket} = connect(MacSocket, %{"token" => "test-mac-token"})
    assert {:error, %{reason: "not your Mac"}} = subscribe_and_join(socket, "mac:owner2", %{})
    {:ok, other} = Mac.need("owner2", id(), "t1", "x")
    socket = online()
    ref = push(socket, "done", %{"id" => other, "result" => "mine now"})
    assert_reply ref, :error, %{reason: "no work " <> _}
  end
end

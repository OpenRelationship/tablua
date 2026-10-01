defmodule VolvoxServer.DriveTest do
  use ExUnit.Case, async: true

  alias VolvoxServer.Run

  defp id, do: "drive-#{System.unique_integer([:positive])}"

  defp watch(id), do: Phoenix.PubSub.subscribe(VolvoxServer.PubSub, "run:" <> id)

  defp await_done(task) do
    receive do
      {:event, %{task: ^task, keyword: "Drive Done", args: args}} -> args
    after
      5_000 -> flunk("#{task} was never done")
    end
  end

  defp starts(id, task) do
    Run.snapshot(id).events |> Enum.count(&(&1.keyword == "Start Task" and &1.task == task))
  end

  test "a driven task steps itself to done and logs its agent" do
    id = id()
    watch(id)
    {:ok, _} = Run.wake(id)
    assert :ok = Run.drive(id, "t1", "make div safe for zero", "scripted")
    assert await_done("t1") == ["done"]
    {:ok, robot} = Run.robot(id)
    assert robot =~ ~r/Drive Task\s+scripted/
    assert %{tasks: [%{task: "t1", state: "done", result: "pass"}]} = Run.snapshot(id)
    assert :ok = Run.sleep(id)
  end

  test "a run does not sleep while it drives" do
    id = id()
    {:ok, _} = Run.wake(id)
    :ok = Run.drive(id, "t1", "make div safe for zero", "scripted")
    assert {:error, message} = Run.sleep(id)
    assert message =~ "driving t1"
  end

  test "an agent with no such name is refused before anything is logged" do
    id = id()
    {:ok, _} = Run.wake(id)
    assert {:error, message} = Run.drive(id, "t1", "x", "nobody")
    assert message =~ "no agent"
    assert %{events: []} = Run.snapshot(id)
  end

  test "a killed run goes on driving from its log" do
    id = id()
    watch(id)
    {:ok, pid} = Run.wake(id)
    :ok = Run.drive(id, "t1", "make div safe for zero", "scripted")
    assert_receive {:event, %{keyword: "Test Result", args: ["fail" | _]}}, 5_000
    Process.exit(pid, :kill)

    assert await_done("t1") == ["done"]
    assert Run.whereis(id) != pid
    assert starts(id, "t1") == 1
    assert %{tasks: [%{state: "done", result: "pass"}]} = Run.snapshot(id)
  end

  test "a node restart wakes the runs that were awake and they finish" do
    id = id()
    watch(id)
    {:ok, pid} = Run.wake(id)
    :ok = Run.drive(id, "t1", "make div safe for zero", "scripted")
    assert_receive {:event, %{keyword: "Test Result", args: ["fail" | _]}}, 5_000
    # As the node going down stops it: a shutdown, so the supervisor does not bring it back.
    :ok = DynamicSupervisor.terminate_child(VolvoxServer.Run.Supervisor, pid)
    assert Run.whereis(id) == nil

    assert {^id, {:ok, _}} = Enum.find(Run.wake_working(), &(elem(&1, 0) == id))
    assert await_done("t1") == ["done"]
    assert starts(id, "t1") == 1
  end
end

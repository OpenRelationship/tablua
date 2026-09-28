defmodule VolvoxServer.RunTest do
  use ExUnit.Case, async: true

  alias VolvoxServer.{Objects, Run}

  @agent File.read!(Path.expand("../support/lua/scripted_agent.lua", __DIR__))

  defp id, do: "run-#{System.unique_integer([:positive])}"

  defp finish(id, task) do
    case Run.step(id, task) do
      {:ok, {state, true}} -> state
      {:ok, {_state, false}} -> finish(id, task)
    end
  end

  defp await_restart(id, old, tries \\ 100) do
    case Run.whereis(id) do
      pid when is_pid(pid) and pid != old ->
        pid

      _ when tries > 0 ->
        Process.sleep(10)
        await_restart(id, old, tries - 1)
    end
  end

  test "a run steps the coordinator to done and logs every step" do
    id = id()
    {:ok, _} = Run.wake(id, agent: @agent)
    assert {:ok, {"understand", false}} = Run.start_task(id, "t1", "make div safe for zero")
    assert finish(id, "t1") == "done"
    {:ok, robot} = Run.robot(id)
    assert robot =~ "Test Result    fail    ZeroDivisionError in test_div"
    assert robot =~ "Test Result    pass"
    assert %{tasks: [%{task: "t1", state: "done", result: "pass"}]} = Run.snapshot(id)
  end

  test "wake, append, sleep and wake again give the same dump" do
    id = id()
    {:ok, pid} = Run.wake(id, agent: @agent)
    {:ok, _} = Run.start_task(id, "t1", "make div safe for zero")
    {:ok, _} = Run.step(id, "t1")
    {:ok, seq} = Run.append(id, "t1", "Steer", ["guard the zero case"], "user")
    assert is_integer(seq)
    {:ok, before} = Run.dump(id)
    {:ok, events} = Run.robot(id)

    ref = Process.monitor(pid)
    assert :ok = Run.sleep(id)
    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}
    assert Run.whereis(id) == nil
    assert {:ok, _} = Objects.get(Objects.run_key(id))

    refute File.exists?(
             Path.join(Application.fetch_env!(:volvox_server, :work_dir), id <> ".sqlite")
           )

    {:ok, _} = Run.wake(id)
    assert {:ok, ^before} = Run.dump(id)
    assert {:ok, ^events} = Run.robot(id)
    assert {:error, message} = Run.step(id, "t1")
    assert message =~ "without an agent"
  end

  test "a killed run wakes from its file and carries on" do
    id = id()
    {:ok, pid} = Run.wake(id, agent: @agent)
    {:ok, _} = Run.start_task(id, "t1", "make div safe for zero")
    {:ok, _} = Run.step(id, "t1")
    {:ok, _} = Run.step(id, "t1")
    {:ok, before} = Run.dump(id)

    Process.exit(pid, :kill)
    new = await_restart(id, pid)
    assert new != pid
    assert {:ok, ^before} = Run.dump(id)
    assert finish(id, "t1") == "done"
  end

  test "each new event is broadcast on the run's topic" do
    id = id()
    Phoenix.PubSub.subscribe(VolvoxServer.PubSub, "run:" <> id)
    {:ok, _} = Run.wake(id, agent: @agent)
    {:ok, _} = Run.start_task(id, "t1", "make div safe for zero")

    assert_receive {:event,
                    %{
                      seq: 1,
                      keyword: "Start Task",
                      args: ["code", "make div safe for zero"],
                      actor: "agent"
                    }}

    assert_receive {:event, %{seq: 2, keyword: "Enter State", args: ["understand"]}}
    assert_receive {:tasks, [%{task: "t1", state: "understand"}]}
    {:ok, _} = Run.append(id, "t1", "Steer", ["try harder"], "user")
    assert_receive {:event, %{seq: 3, keyword: "Steer", actor: "user"}}
  end

  test "a run id cannot name a path" do
    assert_raise ArgumentError, fn -> Run.wake("../etc") end
  end
end

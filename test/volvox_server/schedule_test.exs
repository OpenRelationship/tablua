defmodule VolvoxServer.ScheduleTest do
  use ExUnit.Case, async: false

  alias VolvoxServer.{Run, Schedule}

  defp id, do: "sched-#{System.unique_integer([:positive])}"

  setup do
    Phoenix.PubSub.subscribe(VolvoxServer.PubSub, "schedule")
    :ok
  end

  test "a job wakes its sleeping run and drives the task within a minute of its time" do
    id = id()
    {:ok, _} = Run.wake(id)
    :ok = Run.sleep(id)
    Phoenix.PubSub.subscribe(VolvoxServer.PubSub, "run:" <> id)
    at = DateTime.add(DateTime.utc_now(), 1, :second)
    {:ok, job} = Schedule.add(id, "nightly", "make div safe for zero", "scripted", at)

    assert_receive {:fired, ^job, due, fired}, 5_000
    assert due == DateTime.to_unix(at)
    assert fired - due <= 60
    task = "nightly-#{due}"
    assert_receive {:event, %{task: ^task, keyword: "Drive Done", args: ["done"]}}, 5_000
    assert [%{job: ^job, error: nil}] = Schedule.fired(job)
    refute Enum.any?(Schedule.jobs(), &(&1.id == job))
  end

  test "a repeating job missed while the node was down fires once and keeps its rhythm" do
    id = id()
    now = System.os_time(:second)
    at = DateTime.from_unix!(now - 3_600)
    {:ok, job} = Schedule.add(id, "hourly", "make div safe for zero", "scripted", at, 600)

    assert_receive {:fired, ^job, due, _}, 5_000
    assert due == now - 3_600
    refute_receive {:fired, ^job, _, _}, 200
    [%{at: next}] = Enum.filter(Schedule.jobs(), &(&1.id == job))
    assert next > now and next - now <= 600
    assert rem(next - due, 600) == 0
    :ok = Schedule.remove(job)
  end

  test "the schedule outlives its process" do
    at = DateTime.add(DateTime.utc_now(), 3_600, :second)
    {:ok, job} = Schedule.add(id(), "later", "x", "scripted", at)
    old = Process.whereis(Schedule)
    Process.exit(old, :kill)
    Process.sleep(50)
    assert Process.whereis(Schedule) not in [nil, old]
    assert Enum.any?(Schedule.jobs(), &(&1.id == job))
    :ok = Schedule.remove(job)
  end

  test "bad jobs are refused" do
    at = DateTime.utc_now()
    assert {:error, _} = Schedule.add("../x", "t", "g", "scripted", at)
    assert {:error, _} = Schedule.add("r", "a task", "g", "scripted", at)
    assert {:error, _} = Schedule.add("r", "t", "g", "scripted", at, 5)
  end
end

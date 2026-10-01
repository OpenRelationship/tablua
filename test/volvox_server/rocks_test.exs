defmodule VolvoxServer.RocksTest do
  # PROJECT.md §13, goal 4: a sleeping rock wakes and answers within 1.5 s; 100 rocks on one
  # node, a sleeping one costing only its file. A rock is a run.
  use ExUnit.Case, async: false

  alias VolvoxServer.{Objects, Run}

  @agent File.read!(Path.expand("../support/lua/scripted_agent.lua", __DIR__))

  defp id, do: "rock-#{System.unique_integer([:positive])}"

  defp finish(id, task) do
    case Run.step(id, task) do
      {:ok, {state, true}} -> state
      {:ok, {_, false}} -> finish(id, task)
    end
  end

  defp ms(fun) do
    {us, value} = :timer.tc(fun)
    {us / 1000, value}
  end

  defp await_down(pid) do
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}, 2_000
  end

  test "a sleeping rock wakes and answers within 1.5 s" do
    wake_and_answer("local objects")
  end

  # The same through Cloudflare R2, as a hosted node keeps its sleeping rocks; needs `npx
  # wrangler login`. Run with `mix test --only r2`.
  @tag :r2
  test "a rock sleeping in R2 wakes and answers within 1.5 s" do
    Application.put_env(:volvox_server, :objects, :r2)
    on_exit(fn -> Application.put_env(:volvox_server, :objects, :local) end)
    id = wake_and_answer("R2")
    VolvoxServer.Objects.R2.delete(Objects.run_key(id))
  end

  defp wake_and_answer(where) do
    id = id()
    {:ok, _} = Run.wake(id, agent: @agent)
    {:ok, _} = Run.start_task(id, "t1", "make div safe for zero")
    "done" = finish(id, "t1")

    times =
      for n <- 1..10 do
        :ok = Run.sleep(id)
        task = "t#{n + 1}"

        {took, {:ok, {"understand", false}}} =
          ms(fn ->
            {:ok, _} = Run.wake(id, agent: @agent)
            Run.start_task(id, task, "make div safe for zero")
          end)

        took
      end

    worst = Enum.max(times)

    IO.puts(
      "\n  wake and answer from #{where}, 10 times: median #{median(times)} ms, worst #{Float.round(worst, 1)} ms"
    )

    assert worst <= 1_500
    :ok = Run.sleep(id)
    id
  end

  test "a quiet rock goes to sleep by itself" do
    id = id()
    {:ok, pid} = Run.wake(id, agent: @agent, idle_ms: 50)
    {:ok, _} = Run.start_task(id, "t1", "make div safe for zero")
    await_down(pid)
    assert Run.whereis(id) == nil
    assert {:ok, _} = Objects.get(Objects.run_key(id))
  end

  test "a hundred rocks on one node; a sleeping rock is only its file" do
    ids = for _ <- 1..100, do: id()
    before = :erlang.memory(:total)

    {took, _} =
      ms(fn ->
        ids
        |> Task.async_stream(
          fn id ->
            {:ok, _} = Run.wake(id, agent: @agent)
            {:ok, _} = Run.start_task(id, "t1", "make div safe for zero")
            "done" = finish(id, "t1")
          end,
          max_concurrency: System.schedulers_online(),
          timeout: 60_000
        )
        |> Stream.run()
      end)

    pids = Enum.map(ids, &Run.whereis/1)
    assert Enum.all?(pids, &is_pid/1)
    awake = Enum.sum(for pid <- pids, do: elem(Process.info(pid, :memory), 1))
    total = :erlang.memory(:total) - before

    for id <- ids, do: :ok = Run.sleep(id)
    assert Enum.all?(ids, &(Run.whereis(&1) == nil))
    bytes = for id <- ids, do: byte_size(elem(Objects.get(Objects.run_key(id)), 1))

    IO.puts(
      "\n  100 rocks: each woke and finished a task in #{round(took)} ms all told;" <>
        " awake #{div(awake, 100)} B of process each, node grew #{div(total, 1_048_576)} MB;" <>
        " asleep no process, a #{div(Enum.sum(bytes), 100)} B file each"
    )

    assert Enum.max(bytes) < 1_048_576
  end

  defp median(xs), do: xs |> Enum.sort() |> Enum.at(div(length(xs), 2)) |> Float.round(1)
end

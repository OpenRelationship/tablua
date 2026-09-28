defmodule VolvoxServerWeb.RunLiveTest do
  use VolvoxServerWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  alias VolvoxServer.Run

  @agent File.read!(Path.expand("../../support/lua/scripted_agent.lua", __DIR__))

  test "the run page shows the log and the plan state, and an appended event appears live", %{
    conn: conn
  } do
    id = "live-#{System.unique_integer([:positive])}"
    {:ok, _} = Run.wake(id, agent: @agent)
    {:ok, _} = Run.start_task(id, "t1", "make div safe for zero")

    {:ok, view, html} = live(conn, ~p"/runs/#{id}")
    assert html =~ "Start Task"
    assert html =~ "make div safe for zero"
    assert has_element?(view, "#task-t1 li.current", "understand")
    refute html =~ "guard the zero case"

    {:ok, seq} = Run.append(id, "t1", "Steer", ["guard the zero case"], "user")
    assert has_element?(view, "#event-#{seq}", "guard the zero case")
    assert has_element?(view, "#event-#{seq} td", "user")

    {:ok, _} = Run.step(id, "t1")
    assert has_element?(view, "#task-t1 li.current", "choose_scaffold")
    assert has_element?(view, "#events td", "Decide")
  end

  test "an unknown run opens empty", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/runs/empty-#{System.unique_integer([:positive])}")
    assert html =~ "No task has started."
  end
end

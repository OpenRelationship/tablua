defmodule MossWeb.OwnersTest do
  # A computer belongs to an account (Arock PROJECT.md §14.7, goal 2): the person who opens a computer no one
  # has claims it; to anyone else it does not exist; the post shows a person only what touches their computers.
  use MossWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Moss.{Mail, Owners}

  defp as(person), do: Plug.Test.init_test_session(build_conn(), person: person)
  defp cid(name), do: "#{name}-#{System.unique_integer([:positive])}"

  test "the first person to open a computer owns it; to another it does not exist" do
    c = cid("own")
    assert {:ok, _view, html} = live(as("tester"), "/computers/#{c}")
    assert html =~ c
    assert Owners.owner(c) == "tester"

    assert {:error, {:redirect, %{to: "/mail"}}} = live(as("other"), "/computers/#{c}")
    assert Owners.owner(c) == "tester"
  end

  test "a page refuses an id that is not a computer's" do
    assert {:error, {:redirect, %{to: "/mail"}}} = live(as("tester"), "/computers/Not.An.Id")
  end

  test "the post shows a person only letters, routes and senders that touch their computers" do
    {mine, theirs, far} = {cid("mine"), cid("theirs"), cid("far")}
    :ok = Owners.claim(mine, "tester")
    :ok = Owners.claim(theirs, "other")
    :ok = Owners.claim(far, "other")

    Mail.route(mine, theirs, "audit")
    Mail.route(theirs, far, "audit")
    {_, _} = Mail.post(mine, theirs, "lunch", "friday?")
    {_, _} = Mail.post(theirs, far, "secret plans", "only for far")

    {:ok, _view, html} = live(as("tester"), "/mail")
    assert html =~ "lunch"
    refute html =~ "secret plans"
    refute html =~ far

    {:ok, view, _html} = live(as("tester"), "/mail")
    render_submit(view, "route", %{"sender" => theirs, "recipient" => mine, "mode" => "audit"})
    refute Enum.any?(Mail.routes(), &(&1["sender"] == theirs and &1["recipient"] == mine))
  end

  test "claiming is first come; the owner's claim stands" do
    c = cid("claim")
    assert :ok = Owners.claim(c, "a")
    assert :ok = Owners.claim(c, "a")
    assert {:error, :taken} = Owners.claim(c, "b")
    assert Owners.mine(c, "a")
    refute Owners.mine(c, "b")
    assert c in Owners.owned("a")
  end
end

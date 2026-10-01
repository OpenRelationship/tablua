defmodule MossWeb.MailLiveTest do
  use MossWeb.ConnCase, async: false
  import Phoenix.LiveViewTest

  alias Moss.Mail

  test "a person sees what Jev held and delivers it", %{conn: conn} do
    n = System.unique_integer([:positive])
    {a, b} = {"page-a#{n}", "page-b#{n}"}
    :ok = Mail.route(a, b, "screen")
    {:screening, id} = Mail.post(a, b, "maybe lunch", "maybe we meet at noon")
    :ok = Mail.screen_now()

    {:ok, view, html} = live(conn, ~p"/mail")
    assert html =~ "maybe we meet at noon"
    assert has_element?(view, "#held-#{id}")

    view |> element("#held-#{id} button", "Deliver it") |> render_click()
    refute has_element?(view, "#held-#{id}")
    assert [%{"id" => ^id}] = Mail.inbox(b)

    view |> form("#route-form", sender: b, recipient: a, mode: "audit") |> render_submit()
    assert {:delivered, _} = Mail.post(b, a, "re", "noon works")
  end
end

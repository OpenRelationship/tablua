defmodule MossWeb.AuthTest do
  # The host's pages are a signed-in person's: a run's log, an agent's computer (where a person may type a
  # command), the post (where a person releases held letters and sets routes).
  use MossWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  @moduletag :signed_out

  test "every page sends a stranger to sign in, live sockets included", %{conn: conn} do
    for path <- ["/mail", "/computers/c1"] do
      conn = get(conn, path)
      assert redirected_to(conn) == "/login?" <> URI.encode_query(%{"to" => path})
    end

    assert {:error, {:redirect, %{to: "/login" <> _}}} = live(conn, "/mail")
  end

  test "a wrong token signs no one in; the right one goes back where the person was", %{
    conn: conn
  } do
    assert html_response(get(conn, "/login?to=/mail"), 200) =~ ~s(name="token")

    conn = post(conn, "/login", %{"token" => "guess", "to" => "/mail"})
    assert html_response(conn, 401) =~ "does not sign anyone in"

    conn = post(build_conn(), "/login", %{"token" => "test-page-token", "to" => "/computers/c1"})
    assert redirected_to(conn) == "/computers/c1"
    assert get_session(conn, :person) == "tester"

    conn = conn |> recycle() |> get("/mail")
    assert html_response(conn, 200) =~ "Sign out tester"
  end

  test "signing in never sends a person to another site", %{conn: conn} do
    for to <- ["//evil.example/x", "https://evil.example", "/\\\\evil.example"] do
      conn = post(conn, "/login", %{"token" => "test-page-token", "to" => to})
      assert redirected_to(conn) == "/mail"
    end
  end

  test "a person no longer in the config is signed out at the next page", %{conn: conn} do
    conn = conn |> Plug.Test.init_test_session(person: "removed") |> get("/mail")
    assert redirected_to(conn) =~ "/login"
  end

  test "signing out ends the session", %{conn: conn} do
    conn = post(conn, "/login", %{"token" => "test-page-token"})
    conn = conn |> recycle() |> delete("/logout")
    assert redirected_to(conn) == "/login"
    assert conn |> recycle() |> get("/mail") |> redirected_to() =~ "/login"
  end
end

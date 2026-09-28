defmodule VolvoxServer.FetchTest do
  @moduledoc "The fetch port under Volvox's ports.jev and ports.call, with Req.Test in place of OpenRouter."
  use ExUnit.Case, async: false

  alias VolvoxServer.LuaHost

  setup do
    old = System.get_env("OPENROUTER_API_KEY")
    System.put_env("OPENROUTER_API_KEY", "test-key")

    on_exit(fn ->
      if old,
        do: System.put_env("OPENROUTER_API_KEY", old),
        else: System.delete_env("OPENROUTER_API_KEY")
    end)
  end

  defp answer(conn) do
    Req.Test.json(conn, %{
      "model" => "typesafe/jev-1.13",
      "answers" => %{"go" => %{"choice" => "yes", "confidence" => 0.8}}
    })
  end

  test "ports.jev sends the typed question with the key and reads the answer" do
    Req.Test.stub(VolvoxServer.Fetch, fn conn ->
      assert conn.method == "POST"
      assert conn.request_path == "/api/alpha/decisions"
      assert Plug.Conn.get_req_header(conn, "authorization") == ["Bearer test-key"]
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      sent = Jason.decode!(body)
      assert sent["model"] == "typesafe/jev-1.13"
      assert sent["state"] == "Goal: x"
      assert sent["questions"]["go"]["type"] == "choice"
      answer(conn)
    end)

    assert {:ok, ["yes", 1, 200]} =
             LuaHost.call(:decide, ["Goal: x", "go", "Go?", %{"yes" => "a", "no" => "b"}])
  end

  test "a 503 is retried once through the host's sleep" do
    Req.Test.expect(VolvoxServer.Fetch, 2, fn conn ->
      if Process.get(:answered),
        do: answer(conn),
        else: Process.put(:answered, true) && Plug.Conn.send_resp(conn, 503, "busy")
    end)

    assert {:ok, ["yes", 2, 200]} =
             LuaHost.call(:decide, ["Goal: x", "go", "Go?", %{"yes" => "a", "no" => "b"}])
  end

  test "a transport failure reaches the core as an error without the key" do
    Req.Test.stub(VolvoxServer.Fetch, &Req.Test.transport_error(&1, :econnrefused))

    assert {:error, message} =
             LuaHost.call(:decide, ["Goal: x", "go", "Go?", %{"yes" => "a", "no" => "b"}])

    assert message =~ "jev unreachable"
    refute message =~ "test-key"
  end
end

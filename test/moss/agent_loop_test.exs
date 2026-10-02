defmodule Moss.AgentLoopTest do
  # The live agent tests run Mercury unless a run names a comparison (Arock PROJECT.md §14 item 9: goal 11 was first
  # measured on another model without saying so). This holds it without a call: Mercury is the default, on
  # Inception's own API; a comparison comes only from the loop's own list; nothing in the loop reads the environment.
  use ExUnit.Case, async: true

  @source File.read!(Path.expand("../support/agent_loop.ex", __DIR__))

  test "the agent is Mercury, on Inception's own API" do
    assert Moss.AgentLoop.model() == "mercury-2.5"
    assert URI.parse(Moss.AgentLoop.api()).host == "api.inceptionlabs.ai"
  end

  test "a comparison is only one the loop lists, and no setting picks the model" do
    assert Enum.sort(Moss.AgentLoop.models()) == ["inclusionai/ling-3.0-flash-vl", "mercury-2.5"]
    refute @source =~ "System.get_env"
    assert [_] = Regex.scan(~r/Req\.post!/, @source)

    hosts = Regex.scan(~r{https://([a-z.]+)/}, @source, capture: :all_but_first) |> List.flatten()
    assert Enum.sort(Enum.uniq(hosts)) == ["api.inceptionlabs.ai", "openrouter.ai"]

    assert_raise RuntimeError, ~r/is not a model the loop runs/, fn ->
      Moss.AgentLoop.run("nobody", "", "", model: "moonshotai/kimi-k2.7-code")
    end
  end

  test "a request's cost is the provider's own, else its list price on the usage" do
    usage = %{
      "prompt_tokens" => 1_000_000,
      "completion_tokens" => 1_000_000,
      "prompt_tokens_details" => %{"cached_tokens" => 500_000}
    }

    assert_in_delta Moss.AgentLoop.cost(usage), 0.02 + 0.002 + 0.15, 1.0e-9

    assert Moss.AgentLoop.cost(Map.put(usage, "cost", 0.5), "inclusionai/ling-3.0-flash-vl") ==
             0.5

    assert Moss.AgentLoop.cost(%{}) == 0
  end
end

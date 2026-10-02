defmodule Moss.RockmailTest do
  # Arock's PROJECT.md §18: the post's rules are arock-mail's Lua, run in the core's state; Moss gathers the facts,
  # stores and delivers. These tests hold that the Elixir path really asks arock-mail, and that arock-mail's secret
  # patterns find exactly what the regular expressions Moss used before it found.
  use ExUnit.Case, async: false

  alias Moss.Mail

  setup do
    Application.put_env(:moss, :mail_test_pid, self())

    on_exit(fn ->
      Application.delete_env(:moss, :mail_lua)
      Application.delete_env(:moss, :mail_test_pid)
    end)

    n = System.unique_integer([:positive])
    %{a: "rock-a#{n}", b: "rock-b#{n}"}
  end

  test "posting a letter asks arock-mail's checks, with the facts from the store", %{a: a, b: b} do
    :ok = Mail.route(a, b, "audit")
    {:delivered, _} = Mail.post(a, b, "one", "first")

    Application.put_env(
      :moss,
      :mail_lua,
      Moss.Lua.build(%{
        "arock-mail.checks" => ~S"""
        return { letter = function(l, f, o)
          return "refused", ("rockmail saw %s to %s, %s, %d sent, rate %d"):format(l.sender, l.recipient, f.mode,
            f.sent_last_minute, o.rate)
        end }
        """
      })
    )

    assert Mail.post(a, b, "two", "second") ==
             {:refused, "rockmail saw #{a} to #{b}, audit, 1 sent, rate 20"}
  end

  test "Jev's batch and what follows from its answers are arock-mail's", %{a: a, b: b} do
    :ok = Mail.route(a, b, "screen")
    {:screening, id} = Mail.post(a, b, "plan", "lunch at noon")

    Application.put_env(
      :moss,
      :mail_lua,
      Moss.Lua.build(%{
        "arock-mail.screen" => ~S"""
        return {
          state = function(letters) return "arock-mail's state" end,
          questions = function(letters)
            local q = {}
            for _, l in ipairs(letters) do q["l" .. l.id] = { kind = "choice", text = "?", options = {} } end
            return q
          end,
          verdict = function(l, answer)
            return { state = "held", verdict = "rockmail held it", reason = "said rockmail" }
          end,
        }
        """
      })
    )

    :ok = Mail.screen_now()

    assert %{"state" => "held", "reason" => "said rockmail", "verdict" => "rockmail held it"} =
             Enum.find(Mail.sent(a), &(&1["id"] == id))
  end

  # the regular expressions Moss's checks used before arock-mail, kept here as the reference
  @secrets [
    {~r/\bsk-[A-Za-z0-9_-]{20,}/, "an API key"},
    {~r/\b(ghp|gho|ghs|ghu|github_pat)_[A-Za-z0-9_]{20,}/, "a GitHub token"},
    {~r/\bAKIA[0-9A-Z]{16}\b/, "an AWS key"},
    {~r/\bxox[abposr]-[A-Za-z0-9-]{10,}/, "a Slack token"},
    {~r/-----BEGIN [A-Z ]*PRIVATE KEY-----/, "a private key"},
    {~r/\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/, "a signed token"},
    {~r/\bBearer\s+[A-Za-z0-9._~+\/-]{20,}/i, "a bearer token"}
  ]

  # pieces that make near misses and hits for every pattern
  @pieces [
    ~w(sk- gh p_ o_ s_ u_ github_pat_ AKIA xoxb- xoxz- eyJ . - _ a Z 0 x ! / + ~ Bearer bEaReR) ++
      [" ", "\t", "\n", "é", "aaaaaaaaaa", "AAAAAAAA", "0123456789"],
    [
      "-----BEGIN ",
      "PRIVATE KEY-----",
      "RSA ",
      " ",
      "-",
      "PRIVATE",
      "eyJ",
      ".eyJ",
      ".",
      "aaaaaaaaa",
      "a"
    ] ++
      ["_", "x", "AKIA", "AAAAAAAA", "0", "é", "-----", "eyJaaaaaaaaaa"],
    # long runs of near misses, past the budget after which arock-mail scans instead of trying each
    [
      "sk-a ",
      "-eyJaaaaaaaaaa",
      ".x",
      ".eyJ",
      "aaaaaaaaaa",
      "ghp_a ",
      "Bearer ",
      "xoxb-a ",
      "AKIAA ",
      "."
    ] ++
      ["-----BEGIN A ", "PRIVATE KEY-----", "-", " ", "\t", "AAAAAAAAAAAAAAAA", "a"]
  ]

  test "arock-mail's secret patterns agree with the regular expressions they replaced" do
    :rand.seed(:exsss, {18, 10, 1})

    texts =
      for {pieces, most} <- Enum.zip(@pieces, [40, 40, 1500]),
          _ <- 1..div(120_000, most),
          do: Enum.map_join(1..:rand.uniform(most), "", fn _ -> Enum.random(pieces) end)

    lua = Lua.set!(Moss.Lua.base(), [:__texts], texts)

    {[found], _} =
      Lua.eval!(lua, ~S"""
      local checks, out = require("arock-mail.checks"), {}
      for i, t in ipairs(__texts) do out[i] = checks.secret(t) or "-" end
      return table.concat(out, "\n")
      """)

    want =
      Enum.map(texts, fn t ->
        Enum.find_value(@secrets, "-", fn {re, w} -> Regex.match?(re, t) && w end)
      end)

    assert String.split(found, "\n") == want
    # every pattern was exercised
    assert MapSet.new(want) == MapSet.new(["-" | Enum.map(@secrets, &elem(&1, 1))])
  end
end

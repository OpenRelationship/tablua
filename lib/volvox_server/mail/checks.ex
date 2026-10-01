defmodule VolvoxServer.Mail.Checks do
  @moduledoc """
  The checks every letter passes before Jev sees it, free and at once
  (PROJECT.md §14.5): a route allows it, it is not too big, its sender is not
  writing too fast, and it carries nothing shaped like a key or token.
  `letter(conn, sender, recipient, subject, body)` gives `{:ok, mode}`, the
  route's mode (`screen` for a flagged sender whatever the route says), or
  `{:refused, reason}`.
  """
  alias VolvoxServer.Mail.Store

  @size 64 * 1024

  # what keys and tokens look like: model and cloud keys, chat tokens, private keys, JWTs, bearer headers
  @secrets [
    {~r/\bsk-[A-Za-z0-9_-]{20,}/, "an API key"},
    {~r/\b(ghp|gho|ghs|ghu|github_pat)_[A-Za-z0-9_]{20,}/, "a GitHub token"},
    {~r/\bAKIA[0-9A-Z]{16}\b/, "an AWS key"},
    {~r/\bxox[abposr]-[A-Za-z0-9-]{10,}/, "a Slack token"},
    {~r/-----BEGIN [A-Z ]*PRIVATE KEY-----/, "a private key"},
    {~r/\beyJ[A-Za-z0-9_-]{10,}\.eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}/, "a signed token"},
    {~r/\bBearer\s+[A-Za-z0-9._~+\/-]{20,}/i, "a bearer token"}
  ]

  def letter(conn, sender, recipient, subject, body) do
    mode = Store.mode(conn, sender, recipient)

    cond do
      sender == recipient ->
        {:refused, "a letter to oneself is a note; keep it on the computer"}

      mode == nil ->
        {:refused, "no route lets #{sender} write to #{recipient}"}

      byte_size(subject) + byte_size(body) > @size ->
        {:refused, "a letter is at most #{div(@size, 1024)} KB"}

      Store.sent_since(conn, sender, Store.now() - 60_000) >= rate() ->
        {:refused,
         "#{sender} sent #{rate()} letters in the last minute; wait before sending more"}

      secret = secret(subject <> "\n" <> body) ->
        {:refused, "it carries what looks like #{secret}; keys never travel by mail"}

      Store.flagged?(conn, sender) ->
        {:ok, "screen"}

      true ->
        {:ok, mode}
    end
  end

  defp secret(text),
    do: Enum.find_value(@secrets, fn {re, what} -> if Regex.match?(re, text), do: what end)

  defp rate, do: Application.get_env(:volvox_server, :mail_rate, 20)
end

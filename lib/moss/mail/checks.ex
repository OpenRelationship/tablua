defmodule Moss.Mail.Checks do
  @moduledoc """
  The checks every letter passes before Jev sees it, free and at once
  (PROJECT.md §14.5): not to oneself, a route allows it, it is not too big,
  its sender is not writing too fast, and it carries nothing shaped like a key
  or token. The rules are arock-mail's (`arock-mail.checks`, PROJECT.md §18); this
  module looks up the facts they need in the post's store.
  `letter(conn, sender, recipient, subject, body)` gives `{:ok, mode}`, the
  route's mode (`screen` for a flagged sender whatever the route says), or
  `{:refused, reason}`.
  """
  alias Moss.Mail.{Rockmail, Store}

  def letter(conn, sender, recipient, subject, body) do
    facts = %{
      "mode" => Store.mode(conn, sender, recipient),
      "sent_last_minute" => Store.sent_since(conn, sender, Store.now() - 60_000),
      "flagged" => Store.flagged?(conn, sender)
    }

    Rockmail.check(
      %{"sender" => sender, "recipient" => recipient, "subject" => subject, "body" => body},
      facts,
      %{"rate" => rate()}
    )
  end

  defp rate, do: Application.get_env(:moss, :mail_rate, 20)
end

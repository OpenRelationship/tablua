defmodule Moss.Mail.Screen do
  @moduledoc """
  Jev reading the post (PROJECT.md §14.5), by arock-mail's rules
  (`arock-mail.screen`, PROJECT.md §18). `ask(letters, conn)` puts a batch in
  one call: one state that shows every letter with what its sender sent before
  it, and one question per letter (deliver, hold for a person, refuse).
  `apply(conn, [{letter, answer}])` acts on the answers:

    * a screened letter is delivered or refused when Jev is sure, held for a
      person when it is not;
    * an audited letter is already delivered: a sure hold or refuse takes it
      back to `held` if it is still unread;
    * a sure refuse flags its sender, whose letters are screened from then on.

  The model is config `mail_jev` (a module with `decide(state, questions)`),
  `Moss.Mail.Jev` by default; `mail_sure` is the confidence acted on (0.6).
  """
  alias Moss.Mail.{Rockmail, Store}

  @history 5

  def ask(letters, conn) do
    history = Map.new(letters, &{&1["id"], Store.before(conn, &1["sender"], &1["id"], @history)})
    {state, questions} = Rockmail.ask(letters, history)
    jev().decide(state, questions)
  end

  @doc "Acts on Jev's answer for each letter; gives back each letter's new state, in order."
  def apply(conn, pairs) do
    verdicts = Rockmail.verdicts(pairs, sure())

    for {{l, _answer}, v} <- Enum.zip(pairs, verdicts) do
      fields =
        if(v["state"] != l["state"], do: [state: v["state"]], else: []) ++
          if v["reason"], do: [reason: v["reason"]], else: []

      :ok = Store.set(conn, l["id"], [audited: 1, verdict: v["verdict"]] ++ fields)
      if v["flag"], do: Store.flag(conn, l["sender"], v["flag"])
      v["state"]
    end
  end

  defp sure, do: Application.get_env(:moss, :mail_sure, 0.6)
  defp jev, do: Application.get_env(:moss, :mail_jev, Moss.Mail.Jev)
end

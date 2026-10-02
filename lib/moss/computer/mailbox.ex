defmodule Moss.Computer.Mailbox do
  @moduledoc """
  `mail` on an agent's computer: its inbox at the post (the host's, `Moss.Host`; PROJECT.md §14.5); `help mail` is its help.
  `run(args, stdin, state)` gives back `{code, out, err}`.
  """

  @help """
  The post: the computer's id is its address; a letter goes only along a route the person set.

      mail                          the inbox: number, sender, subject; * marks unread
      mail read <n>                 one letter, marked read
      mail send <to> [subject...]   sends what comes on stdin (or after -m): an org entry, or a message for one
      mail sent                     what this computer sent, and where each letter is now
      mail board                    every task sent or received, its state now, as org

  A letter is one org entry: its headline the subject, TODO when it hands over work. A reply names the task it
  answers in :TASK: (the task's address, org:fern/mail/7, its :ID:), and its keyword (WAIT, DONE, DROP) is the
  task's new state. The post stamps :FROM:, :TO: and :ID:. Every org: link must name something on the node.

      echo '* TODO Build the plants page' | mail send moss-1
  mail send fern -m '* DONE Built it
  :PROPERTIES:
  :TASK: org:fern/mail/7
  :END:
  It lists the plants at /plants/.'

  A longer letter: write it with the tool's files (files/reply.txt), then mail send fern < files/reply.txt.
  """

  def help, do: @help
  alias Moss.Host, as: Mail

  def run([], _stdin, state) do
    case Mail.inbox(state.id) do
      [] -> {0, "no mail\n", ""}
      letters -> {0, Enum.map_join(letters, &line/1), ""}
    end
  end

  def run(["read", n | _], _stdin, state) do
    with {id, ""} <- Integer.parse(n),
         {:ok, l} <- Mail.read(state.id, id) do
      body = if String.ends_with?(l["body"], "\n"), do: l["body"], else: l["body"] <> "\n"
      {0, body, ""}
    else
      _ -> {1, "", "mail: no letter #{n} in this inbox\n"}
    end
  end

  def run(["send", to | rest], stdin, state) do
    {subject, body} =
      case Enum.split_while(rest, &(&1 != "-m")) do
        {words, ["-m" | body]} -> {Enum.join(words, " "), Enum.join(body, " ")}
        {words, []} -> {Enum.join(words, " "), stdin}
      end

    cond do
      String.trim(body) == "" ->
        {2, "", "mail: the letter has no body (pipe it in, or give it after -m)\n"}

      subject == "" and not String.starts_with?(String.trim_leading(body), "* ") ->
        {2, "", "mail: send <to> <subject...>, or a body that is an org entry (* its subject)\n"}

      true ->
        case Moss.Computer.mail(state.id, to, subject, body) do
          {:delivered, id} -> {0, "sent #{id} to #{to}: delivered\n", ""}
          {:screening, id} -> {0, "sent #{id} to #{to}: waiting for the post to read it\n", ""}
          {:refused, why} -> {1, "", "mail: refused: #{why}\n"}
        end
    end
  end

  def run(["sent" | _], _stdin, state) do
    case Mail.sent(state.id) do
      [] ->
        {0, "nothing sent\n", ""}

      letters ->
        {0,
         Enum.map_join(letters, fn l ->
           "#{pad(l["id"])}  to #{l["recipient"]}  #{l["subject"]}  (#{where(l)})\n"
         end), ""}
    end
  end

  def run(["board" | _], _stdin, state), do: {0, Mail.board(state.id), ""}

  def run(_, _stdin, _state),
    do:
      {2, "",
       "mail: mail | mail read <n> | mail send <to> [subject...] | mail sent | mail board\n"}

  defp line(l),
    do:
      "#{if l["read"] == 0, do: "*", else: " "} #{pad(l["id"])}  #{l["sender"]}  #{l["subject"]}\n"

  defp where(%{"state" => "refused"} = l), do: "refused: #{l["reason"]}"
  defp where(%{"state" => "held"}), do: "held for a person"
  defp where(%{"state" => "screening"}), do: "waiting for the post"
  defp where(%{"read" => 1}), do: "read"
  defp where(_), do: "delivered"

  defp pad(id), do: String.pad_leading(to_string(id), 4)
end

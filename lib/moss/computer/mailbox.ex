defmodule Moss.Computer.Mailbox do
  @moduledoc """
  `mail` on an agent's computer: its inbox at the post (`Moss.Mail`,
  PROJECT.md §14.5). The computer's id is the agent's address.

      mail                          the inbox: number, sender, subject; * marks unread
      mail read <n>                 one letter, marked read
      mail send <to> <subject...>   sends what comes on stdin (or after -m) as the body
      mail sent                     what this computer sent, and where each letter is now

  `run(args, stdin, state)` gives back `{code, out, err}`.
  """
  alias Moss.Mail

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
      {0, "from: #{l["sender"]}\nsubject: #{l["subject"]}\n\n" <> body, ""}
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
      subject == "" ->
        {2, "", "mail: send <to> <subject...> (the body on stdin, or after -m)\n"}

      String.trim(body) == "" ->
        {2, "", "mail: the letter has no body (pipe it in, or give it after -m)\n"}

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

  def run(_, _stdin, _state),
    do: {2, "", "mail: mail | mail read <n> | mail send <to> <subject...> | mail sent\n"}

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

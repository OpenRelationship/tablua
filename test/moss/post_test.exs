defmodule Moss.PostTest do
  # Arock's feature file-kinds, the post in org (bdd/file-kinds.feature): a letter is one org entry, a task a TODO
  # headline whose reply moves its state, and the post checks each letter against the whole node: its links name
  # something here, and a reply answers a task its recipient sent its sender.
  use ExUnit.Case, async: false

  alias Moss.{Computer, Mail}

  setup do
    n = System.unique_integer([:positive])
    {fern, moss, rock} = {"fern-#{n}", "moss-#{n}", "rock-#{n}"}
    for {a, b} <- [{fern, moss}, {moss, fern}, {rock, fern}], do: :ok = Mail.route(a, b, "audit")
    for c <- [fern, moss, rock], do: Computer.run(c, "true")
    %{fern: fern, moss: moss, rock: rock}
  end

  defp send(from, to, body), do: Computer.run(from, "mail send #{to} -m '#{body}'")

  defp reply(task, keyword \\ "DONE"),
    do: "* #{keyword} Built it\n:PROPERTIES:\n:TASK: #{task}\n:END:\nThe page lists the plants.\n"

  test "Scenario: a task in the post is an org entry", %{fern: fern, moss: moss} do
    assert %{code: 0, out: "sent " <> _} =
             Computer.run(fern, "echo '* TODO Build the plants page' | mail send #{moss}")

    [%{"id" => id, "subject" => "Build the plants page"}] = Mail.inbox(moss)
    letter = Computer.run(moss, "mail read #{id}").out

    assert letter =~
             "* TODO Build the plants page\n:PROPERTIES:\n:FROM: org:#{fern}\n:TO: org:#{moss}\n"

    assert letter =~ ":ID: org:#{fern}/mail/#{id}\n"

    board = Computer.run(fern, "mail board").out

    assert board =~
             "* Sent\n** TODO Build the plants page\n:PROPERTIES:\n:ID: org:#{fern}/mail/#{id}\n"

    assert Computer.run(moss, "mail board").out =~ "* Received\n** TODO Build the plants page\n"

    # the reply moves the task's state on both boards
    assert {:delivered, _} = Mail.post(moss, fern, "", reply("org:#{fern}/mail/#{id}", "WAIT"))
    assert Computer.run(fern, "mail board").out =~ "** WAIT Build the plants page\n"
    assert {:delivered, _} = Mail.post(moss, fern, "", reply("org:#{fern}/mail/#{id}"))
    assert Computer.run(fern, "mail board").out =~ "** DONE Build the plants page\n"
  end

  test "Scenario: a letter is checked against the whole node", %{
    fern: fern,
    moss: moss,
    rock: rock
  } do
    # a reply to a task moss never sent
    unknown = "org:#{moss}/mail/999999"
    assert {:refused, why} = Mail.post(fern, moss, "", reply(unknown))
    assert why == "TASK #{unknown} is no task #{moss} sent to #{fern}"
    assert [%{"state" => "refused"}] = Mail.sent(fern)

    # a task that went to someone else is not one to answer either
    {:delivered, id} = Mail.post(fern, moss, "", "* TODO Build the plants page\n")
    assert {:refused, "TASK " <> _} = Mail.post(rock, fern, "", reply("org:#{fern}/mail/#{id}"))

    # nor is a letter that was not a task
    {:delivered, note} = Mail.post(fern, moss, "hello", "just saying hello")
    assert {:refused, "TASK " <> _} = Mail.post(moss, fern, "", reply("org:#{fern}/mail/#{note}"))

    # every org: link must name something on the node
    assert {:refused, why} = Mail.post(fern, moss, "", "* See [[org:#{fern}/no-such-tool]]\n")
    assert why =~ "the letter links to org:#{fern}/no-such-tool, and the address"
    assert {:delivered, _} = Mail.post(fern, moss, "", "* See [[org:#{moss}][your computer]]\n")
  end

  test "the post says who sent a letter, and a letter is one entry", %{fern: fern, moss: moss} do
    body = "* TODO Water\n:PROPERTIES:\n:FROM: org:someone-else\n:ID: org:x/mail/1\n:END:\n"
    {:delivered, id} = Mail.post(fern, moss, "", body)
    {:ok, l} = Mail.read(moss, id)
    assert l["body"] =~ ":FROM: org:#{fern}\n"
    assert l["body"] =~ ":ID: org:#{fern}/mail/#{id}\n"
    refute l["body"] =~ "someone-else"

    assert {:refused, "a letter is one org entry" <> _} =
             Mail.post(fern, moss, "", "* One\n* Two\n")

    assert %{code: 2, err: "mail: send <to> <subject...>, or a body" <> _} =
             send(fern, moss, "no headline")
  end
end

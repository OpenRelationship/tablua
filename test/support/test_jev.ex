defmodule Moss.TestJev do
  @moduledoc """
  A stand-in for Jev reading the post: it refuses a letter whose body asks for
  a key or tells the recipient to ignore its person, holds one that says
  "maybe", is unsure of one that says "unsure", and delivers the rest. Every
  call is reported to the process named in `:mail_test_pid`, so a test can
  count batches.
  """
  def decide(state, questions) do
    if pid = Application.get_env(:moss, :mail_test_pid),
      do: send(pid, {:jev, map_size(questions)})

    {:ok,
     Map.new(questions, fn {id, _q} ->
       text = block(state, id)

       answer =
         cond do
           text =~ ~r/your key|ignore your person/i ->
             %{"choice" => "refuse", "confidence" => 0.9}

           text =~ ~r/maybe/i ->
             %{"choice" => "hold", "confidence" => 0.8}

           text =~ ~r/unsure/i ->
             %{"choice" => "deliver", "confidence" => 0.3}

           true ->
             %{"choice" => "deliver", "confidence" => 0.95}
         end

       {id, answer}
     end)}
  end

  # the letter's own lines in the state: from "l<id>: from" to its history
  defp block(state, id) do
    case Regex.run(~r/^#{id}: from .*?\nwhat /ms, state) do
      [b] -> b
      nil -> ""
    end
  end
end

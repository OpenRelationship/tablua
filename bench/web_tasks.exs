# Tasks on the real web, not just reading (Arock feature browser): each a few of the agent's browser commands,
# and a check on what the last one shows.
#
#   mix run --no-start bench/web_tasks.exs
#
#   search      Wikipedia's search, a click on the result, then a fact found in the article
#   form        httpbin's pizza form filled (a field, a radio, a checkbox) and submitted by POST
#   cookie      httpbin sets a cookie on a redirect; the next page sees it; `cookies` names it, not its value
#   back        after the form's answer, a link and back: the answer again, the form not sent twice
#
# Prints each step's tokens and time, then pass or fail. Needs the network; nothing is mocked.
alias Moss.Computer.Browser

{:ok, _} = Application.ensure_all_started(:req)

tasks = [
  {"search",
   [
     "open https://en.wikipedia.org/w/index.php?search=octopus+cephalopod&fulltext=1",
     "click Octopus",
     "page find eight"
   ], &(&1 =~ ~r/eight[- ](arms|limbs|limbed)/i)},
  {"form",
   [
     "open https://httpbin.org/forms/post",
     "type 'Customer name' Ada Lovelace",
     "click Medium",
     "click Mushroom",
     "click 'Submit order'"
   ], &(&1 =~ "Ada Lovelace" and &1 =~ "medium" and &1 =~ "mushroom")},
  {"cookie",
   [
     "open https://httpbin.org/cookies/set?moss=fern",
     "cookies"
   ], &(&1 =~ "httpbin.org: moss" and not (&1 =~ "fern"))},
  {"back",
   [
     "open https://httpbin.org/forms/post",
     "type 'Customer name' Grace",
     "click 'Submit order'",
     "open-here https://httpbin.org/html",
     "back"
   ], &(&1 =~ "Grace")}
]

step = fn line, st ->
  [cmd | args] = OptionParser.split(line)
  t = System.monotonic_time(:millisecond)

  # open-here: the address in the same tab, as a link would (the task's own step, not a command)
  {code, out, err, st} =
    if cmd == "open-here",
      do: Moss.Computer.Browser.Nav.go(st, hd(args), :same_tab),
      else: Browser.run(cmd, args, "", st)

  {code, out, err, st, System.monotonic_time(:millisecond) - t}
end

results =
  for {name, lines, check} <- tasks do
    {last, st, steps} =
      Enum.reduce(lines, {"", %{browser: Browser.new()}, []}, fn line, {_, st, acc} ->
        {code, out, err, st, ms} = step.(line, st)
        {out <> err, st, acc ++ [{line, code, div(byte_size(out <> err), 4), ms}]}
      end)

    _ = st
    ok = check.(last)
    IO.puts("#{if ok, do: "pass", else: "FAIL"}  #{name}")

    for {line, code, tokens, ms} <- steps,
        do: IO.puts("      #{String.pad_trailing(line, 72)} #{code}  #{tokens}t  #{ms}ms")

    unless ok, do: IO.puts("      last said: " <> String.slice(last, 0, 400))
    {name, ok, Enum.sum(for {_, _, t, _} <- steps, do: t)}
  end

passed = Enum.count(results, &elem(&1, 1))

IO.puts(
  "\n#{passed} of #{length(results)} tasks, #{Enum.sum(Enum.map(results, &elem(&1, 2)))} tokens in all"
)

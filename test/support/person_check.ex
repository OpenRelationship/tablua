defmodule Moss.PersonCheck do
  @moduledoc """
  The build suite's hidden check (Arock's eval/build): what the person does with a shipped page, whatever the agent
  tested. Every ask in the suite asks to add something, so the check opens the page, fills its first form that
  posts (each text field a new name, a number 2, a date today, also for a text field whose placeholder or name
  asks for one; hidden fields as they are), sends it, and opens the page
  again: the app works if the name is now on it. The agent never sees this check.
  """
  alias Moss.Computer

  @doc "`%{status, form, added}` for the page at `path` on computer `id`."
  def uses(id, path) do
    {status, page} = get(id, path)

    case status == 200 && form(page) do
      {action, fields} ->
        name = "Zz#{System.unique_integer([:positive])}"
        # the action resolved against the page as a browser resolves it: pantry?do=add on /pantry is /pantry?do=add
        url = URI.merge("http://app" <> path, action)
        target = url.path || path
        query = if url.query, do: URI.decode_query(url.query), else: %{}
        form = Map.new(fields, &value(&1, name))

        {posted, _, _, _} =
          Computer.serve(id, %{
            "method" => "POST",
            "path" => target,
            "query" => query,
            "form" => form,
            "headers" => %{"hx-request" => "true"}
          })

        {_, after_} = get(id, path)
        %{status: status, form: posted, added: String.contains?(after_, name)}

      _ ->
        %{status: status, form: nil, added: false}
    end
  end

  defp get(id, path) do
    {status, _, body, _} = Computer.serve(id, %{"method" => "GET", "path" => path})
    {status, IO.iodata_to_binary(body)}
  end

  # the first form that posts and has a field a person types in, with its fields: {name, type, value} (a row's
  # delete form, a hidden name and a button, came first on a plants page and is not where a person adds)
  defp form(page) do
    Regex.scan(~r/<form\b([^>]*)>(.*?)<\/form>/s, page)
    |> Enum.find_value(fn [_, attrs, inner] ->
      with [_, action] <- Regex.run(~r/hx-post="([^"]*)"/, attrs),
           fields when fields != [] <- fields(inner),
           true <- Enum.any?(fields, fn {_, t, _} -> t not in ~w(hidden submit checkbox radio) end),
           do: {action, fields},
           else: (_ -> nil)
    end)
  end

  defp fields(inner) do
    for [tag] <- Regex.scan(~r/<(?:input|textarea|select)\b[^>]*>/, inner),
        [_, name] <- [Regex.run(~r/name="([^"]+)"/, tag)] do
      type = with([_, t] <- Regex.run(~r/type="([^"]+)"/, tag), do: t, else: (_ -> "text"))
      val = with([_, v] <- Regex.run(~r/value="([^"]*)"/, tag), do: v, else: (_ -> ""))
      {name, read_as(type, name, tag), val}
    end
  end

  # a text field the person can tell wants a date or a number (its placeholder, or the name its label would show)
  # gets one, as a person would type it: a countdown's date field placeholder="YYYY-MM-DD" is not a name
  defp read_as("text", name, tag) do
    hint = String.downcase(name <> " " <> with([_, h] <- Regex.run(~r/placeholder="([^"]*)"/, tag), do: h, else: (_ -> "")))

    cond do
      hint =~ ~r/yyyy|\bdate\b|\bdue\b|\bday\b|\bwhen\b/ -> "date"
      hint =~ ~r/amount|price|cost|qty|quantity|count|number|how many|\bpages?\b/ -> "number"
      true -> "text"
    end
  end

  defp read_as(type, _, _), do: type

  defp value({n, "hidden", v}, _), do: {n, v}
  defp value({n, "number", _}, _), do: {n, "2"}
  defp value({n, "date", _}, _), do: {n, Date.to_iso8601(Date.utc_today())}

  defp value({n, t, v}, _) when t in ~w(checkbox radio submit),
    do: {n, if(v == "", do: "on", else: v)}

  defp value({n, _, _}, name), do: {n, name}
end

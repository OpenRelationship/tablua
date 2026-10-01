defmodule Moss.HTML.Tokenizer do
  @moduledoc """
  The HTML standard's tokenizer (§13.2.5), in Elixir, for what a page holds: text with its character references,
  start and end tags with attributes in every quoting form, comments and bogus comments, doctypes, CDATA in
  foreign content, and the text of RCDATA (title, textarea), RAWTEXT (style, xmp, iframe, noembed, noframes,
  noscript), script (with its escaped and double-escaped states) and plaintext elements.

  It is driven by the tree builder, which says after each start tag what state the text after it is read in:

      {token, rest, state} = next(rest, state)    # or :eof

  Tokens: `{:start, name, attrs, self_closing?}`, `{:end, name}`, `{:text, text}`, `{:comment, text}`,
  `{:doctype, name}`. Names are lower case; attributes keep their first spelling of a name. The input is
  prepared once by `prepare/1`: valid UTF-8, newlines as `\\n`.
  """

  alias Moss.HTML.CharRef

  @ws [?\s, ?\t, ?\n, ?\f]

  def new(mode \\ :data, last \\ nil), do: %{mode: mode, last: last, foreign: false}

  @doc "The input as the tokenizer reads it: invalid UTF-8 replaced, CR LF and CR made LF."
  def prepare(html) do
    html = if String.valid?(html), do: html, else: String.replace_invalid(html)

    if :binary.match(html, "\r") == :nomatch,
      do: html,
      else: html |> String.replace("\r\n", "\n") |> String.replace("\r", "\n")
  end

  def next(<<>>, _ts), do: :eof
  def next(bin, %{mode: :data} = ts), do: data(bin, [], ts)
  def next(bin, %{mode: :plaintext} = ts), do: {{:text, nul(bin)}, "", ts}
  def next(bin, %{mode: :rcdata} = ts), do: raw(bin, 0, ts, true)
  def next(bin, %{mode: :rawtext} = ts), do: raw(bin, 0, ts, false)
  def next(bin, %{mode: :script} = ts), do: script(bin, 0, :normal, ts)

  # -- data ----------------------------------------------------------------------------------------

  defp data(bin, acc, ts) do
    case :binary.match(bin, pat(:text)) do
      :nomatch ->
        text([acc | bin], "", ts)

      {i, 1} ->
        <<before::binary-size(^i), c, rest::binary>> = bin
        acc = if i == 0, do: acc, else: [acc | before]

        if c == ?& do
          {ref, rest} = CharRef.decode(rest, false)
          data(rest, [acc | ref], ts)
        else
          lt(rest, acc, ts, binary_part(bin, i, byte_size(bin) - i))
        end
    end
  end

  # a "<" in text (`at` the input from it): a tag, a comment or the like, or just the character
  defp lt(rest, acc, ts, at) do
    if starts_markup?(rest) and acc != [] do
      text(acc, at, ts)
    else
      case tag_open(rest, ts) do
        :text -> data(rest, [acc | "<"], ts)
        {:skip, rest} -> data(rest, acc, ts)
        {:eof_text, t} -> text([acc | t], "", ts)
        :eof -> if acc == [], do: :eof, else: text(acc, "", ts)
        {tok, rest} -> {tok, rest, ts}
      end
    end
  end

  defp starts_markup?(<<c, _::binary>>), do: c in [?!, ?/, ??] or alpha?(c)
  defp starts_markup?(_), do: false

  defp text(io, rest, ts) do
    case IO.iodata_to_binary(io) do
      "" -> next(rest, ts)
      t -> {{:text, t}, rest, ts}
    end
  end

  defp tag_open(<<?!, r::binary>>, ts), do: markup(r, ts)
  defp tag_open(<<?/, r::binary>>, _ts), do: end_tag_open(r)
  defp tag_open(<<??, _::binary>> = r, _ts), do: bogus(r)
  defp tag_open(<<c, _::binary>> = r, _ts) when c in ?a..?z or c in ?A..?Z, do: tag(r, :start)
  defp tag_open(_, _ts), do: :text

  defp end_tag_open(<<c, _::binary>> = r) when c in ?a..?z or c in ?A..?Z, do: tag(r, :end)
  defp end_tag_open(<<?>, r::binary>>), do: {:skip, r}
  defp end_tag_open(<<>>), do: {:eof_text, "</"}
  defp end_tag_open(r), do: bogus(r)

  defp markup(<<"--", r::binary>>, _ts), do: comment(r)

  defp markup(<<d::binary-size(7), r::binary>> = all, ts) do
    cond do
      lower(d) == "doctype" -> doctype(r)
      d == "[CDATA[" and ts.foreign -> cdata(r)
      true -> bogus(all)
    end
  end

  defp markup(r, _ts), do: bogus(r)

  # -- comments, doctypes, CDATA -------------------------------------------------------------------

  defp comment(<<?>, r::binary>>), do: {{:comment, ""}, r}
  defp comment(<<"->", r::binary>>), do: {{:comment, ""}, r}

  defp comment(r) do
    case :binary.match(r, pat(:comment_end)) do
      :nomatch ->
        {{:comment, r |> String.replace(~r/(--!|--|-)\z/, "") |> nul()}, ""}

      {i, l} ->
        <<c::binary-size(^i), _::binary-size(^l), rest::binary>> = r
        {{:comment, nul(c)}, rest}
    end
  end

  defp bogus(r) do
    case :binary.match(r, ">") do
      :nomatch ->
        {{:comment, nul(r)}, ""}

      {i, 1} ->
        <<c::binary-size(^i), ?>, rest::binary>> = r
        {{:comment, nul(c)}, rest}
    end
  end

  defp doctype(r) do
    {d, rest} =
      case :binary.match(r, ">") do
        :nomatch -> {r, ""}
        {i, 1} -> {binary_part(r, 0, i), binary_part(r, i + 1, byte_size(r) - i - 1)}
      end

    name = d |> String.split(~r/[\t\n\f ]+/, trim: true) |> List.first("") |> lower() |> nul()
    {{:doctype, name}, rest}
  end

  defp cdata(r) do
    case :binary.match(r, "]]>") do
      :nomatch ->
        {{:text, r}, ""}

      {i, 3} ->
        <<c::binary-size(^i), "]]>", rest::binary>> = r
        if c == "", do: {:skip, rest}, else: {{:text, c}, rest}
    end
  end

  # -- tags ----------------------------------------------------------------------------------------

  defp tag(r, kind) do
    {name, rest} = until(r, :tag_name)

    case attrs(rest, {[], MapSet.new()}) do
      :eof -> :eof
      {_attrs, _sc, rest} when kind == :end -> {{:end, lower(nul(name))}, rest}
      {attrs, sc, rest} -> {{:start, lower(nul(name)), Enum.reverse(attrs), sc}, rest}
    end
  end

  defp attrs(bin, acc) do
    case skip_ws(bin) do
      <<>> -> :eof
      <<?>, r::binary>> -> {elem(acc, 0), false, r}
      <<"/>", r::binary>> -> {elem(acc, 0), true, r}
      <<?/, r::binary>> -> attrs(r, acc)
      <<?=, r::binary>> -> attr_name(r, "=", acc)
      b -> attr_name(b, "", acc)
    end
  end

  defp attr_name(bin, first, acc) do
    {name, rest} = until(bin, :attr_name)
    name = lower(nul(first <> name))

    case skip_ws(rest) do
      <<?=, r::binary>> ->
        case value(skip_ws(r)) do
          :eof -> :eof
          {v, rest} -> attrs(rest, add(acc, name, v))
        end

      r ->
        attrs(r, add(acc, name, ""))
    end
  end

  # a name written twice keeps its first value
  defp add({list, seen} = acc, name, v) do
    if MapSet.member?(seen, name), do: acc, else: {[{name, v} | list], MapSet.put(seen, name)}
  end

  defp value(<<q, r::binary>>) when q in [?", ?'] do
    case :binary.match(r, pat(if(q == ?", do: :dquote, else: :squote))) do
      :nomatch ->
        :eof

      {i, 1} ->
        <<v::binary-size(^i), _, rest::binary>> = r
        {attr_text(v), rest}
    end
  end

  defp value(<<?>, _::binary>> = r), do: {"", r}

  defp value(r) do
    {v, rest} = until(r, :unquoted)
    {attr_text(v), rest}
  end

  defp attr_text(v) do
    case :binary.match(v, pat(:amp)) do
      :nomatch ->
        nul(v)

      {i, 1} ->
        <<before::binary-size(^i), ?&, rest::binary>> = v
        {ref, rest} = CharRef.decode(rest, true)
        nul(before) <> ref <> attr_text(rest)
    end
  end

  # -- RCDATA, RAWTEXT and script text -------------------------------------------------------------

  # text up to the end tag of the element it is in (`</title`, `</style` ... then a space, / or >)
  defp raw(bin, from, ts, rcdata?) do
    case :binary.match(bin, pat(:end_open), scope: {from, byte_size(bin) - from}) do
      :nomatch ->
        {{:text, raw_text(bin, rcdata?)}, "", ts}

      {i, 2} ->
        cond do
          not closes?(bin, i, ts.last) ->
            raw(bin, i + 2, ts, rcdata?)

          i > 0 ->
            {{:text, raw_text(binary_part(bin, 0, i), rcdata?)},
             binary_part(bin, i, byte_size(bin) - i), ts}

          true ->
            end_of_text(bin, ts)
        end
    end
  end

  defp raw_text(t, true), do: t |> data_text() |> nul()
  defp raw_text(t, false), do: nul(t)

  defp data_text(t) do
    case :binary.match(t, pat(:amp)) do
      :nomatch ->
        t

      {i, 1} ->
        <<before::binary-size(^i), ?&, rest::binary>> = t
        {ref, rest} = CharRef.decode(rest, false)
        before <> ref <> data_text(rest)
    end
  end

  defp end_of_text(<<"</", r::binary>>, ts) do
    case tag(r, :end) do
      :eof -> :eof
      {tok, rest} -> {tok, rest, %{ts | mode: :data}}
    end
  end

  # does the "</" at i begin the end tag of `last`?
  defp closes?(_bin, _i, nil), do: false

  defp closes?(bin, i, last) do
    n = byte_size(last)

    case bin do
      <<_::binary-size(^i), "</", name::binary-size(^n), c, _::binary>> ->
        c in [?/, ?> | @ws] and lower(name) == last

      _ ->
        false
    end
  end

  # script data and its escaped (`<!--`) and double-escaped (`<!--<script>`) states (§13.2.5.4, .15-.31)
  defp script(bin, from, st, ts) do
    size = byte_size(bin)
    pats = if st == :normal, do: :script, else: :script_escaped

    case :binary.match(bin, pat(pats), scope: {from, size - from}) do
      :nomatch ->
        {{:text, nul(bin)}, "", ts}

      {i, _} ->
        <<_::binary-size(^i), here::binary>> = bin

        cond do
          match?(<<"<!--", _::binary>>, here) ->
            script(bin, i + 2, if(st == :normal, do: :escaped, else: st), ts)

          match?(<<"-->", _::binary>>, here) ->
            script(bin, i + 3, :normal, ts)

          st != :double and closes?(bin, i, ts.last) ->
            script_end(bin, i, ts)

          st == :double and closes?(bin, i, "script") ->
            script(bin, i + 8, :escaped, ts)

          st == :escaped and opens_script?(here) ->
            script(bin, i + 7, :double, ts)

          true ->
            script(bin, i + 1, st, ts)
        end
    end
  end

  defp script_end(bin, 0, ts), do: end_of_text(bin, ts)

  defp script_end(bin, i, ts),
    do: {{:text, nul(binary_part(bin, 0, i))}, binary_part(bin, i, byte_size(bin) - i), ts}

  defp opens_script?(<<?<, s::binary-size(6), c, _::binary>>),
    do: c in [?/, ?> | @ws] and lower(s) == "script"

  defp opens_script?(_), do: false

  # -- helpers -------------------------------------------------------------------------------------

  # a name or unquoted value runs to the first byte that ends it; names are short, so a byte loop beats a search
  defp until(bin, stops), do: split(bin, stop(bin, 0, stops))

  defp stop(bin, i, stops) do
    case bin do
      <<_::binary-size(^i), c, _::binary>> ->
        if stop?(c, stops), do: i, else: stop(bin, i + 1, stops)

      _ ->
        i
    end
  end

  defp stop?(c, _) when c in @ws or c == ?>, do: true
  defp stop?(?/, stops), do: stops != :unquoted
  defp stop?(?=, stops), do: stops == :attr_name
  defp stop?(_, _), do: false

  defp split(bin, i), do: {binary_part(bin, 0, i), binary_part(bin, i, byte_size(bin) - i)}

  defp skip_ws(<<c, r::binary>>) when c in @ws, do: skip_ws(r)
  defp skip_ws(r), do: r

  defp alpha?(c), do: c in ?a..?z or c in ?A..?Z

  @doc "ASCII lower case, as the standard folds names."
  def lower(s), do: String.downcase(s, :ascii)

  @pats %{
    text: ["<", "&"],
    comment_end: ["-->", "--!>"],
    dquote: "\"",
    squote: "'",
    amp: "&",
    nul: <<0>>,
    end_open: "</",
    script: ["<!--", "</"],
    script_escaped: ["-->", "<"],
    escape: ["&", "<", ">"],
    escape_attr: ["&", "\"", "<", ">"]
  }

  @doc "A search pattern by name, for `:binary.match/3`: compiled once and kept."
  def pat(name) do
    case :persistent_term.get({__MODULE__, name}, nil) do
      nil ->
        cp = :binary.compile_pattern(Map.fetch!(@pats, name))
        :persistent_term.put({__MODULE__, name}, cp)
        cp

      cp ->
        cp
    end
  end

  defp nul(s),
    do: if(:binary.match(s, pat(:nul)) == :nomatch, do: s, else: String.replace(s, <<0>>, "�"))
end

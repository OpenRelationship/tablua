defmodule Moss.Sql.Date do
  @moduledoc """
  date(), time(), datetime(), julianday(), unixepoch() and strftime(), by
  SQLite's own arithmetic (date.c): a time is milliseconds of Julian day, read
  from 'now', `YYYY-MM-DD[ HH:MM[:SS[.SSS]]][Z|±HH:MM]`, `HH:MM[:SS]` or a
  number (a Julian day, or Unix seconds before 'unixepoch'); the modifiers
  are `±N days|hours|minutes|seconds|months|years`, `start of
  day|month|year`, `weekday N`, `unixepoch`, `subsec`, and `utc` and
  `localtime`, which change nothing (a node keeps UTC). Anything else is NULL.
  """
  alias Moss.Sql.Value

  @unix_jd 210_866_760_000_000
  @day 86_400_000

  def now(:datetime, ms), do: fmt_datetime(ms + @unix_jd, false)
  def now(:date, ms), do: fmt_date(ms + @unix_jd)
  def now(:time, ms), do: fmt_time(ms + @unix_jd, false)

  def call(f, args, now) do
    case eval(args, now) do
      nil ->
        nil

      {jd, subsec} ->
        case f do
          "date" -> fmt_date(jd)
          "time" -> fmt_time(jd, subsec)
          "datetime" -> fmt_datetime(jd, subsec)
          "julianday" -> jd / @day
          "unixepoch" -> if subsec, do: (jd - @unix_jd) / 1000, else: div(jd - @unix_jd, 1000)
        end
    end
  end

  def strftime(nil, _, _), do: nil

  def strftime(fmt, args, now) do
    case eval(args, now) do
      nil -> nil
      {jd, _} -> format(Value.to_text(fmt), jd, [])
    end
  end

  # the time value and its modifiers, as {julian day ms, subsec?}, or nil
  defp eval([], now), do: eval(["now"], now)
  defp eval([nil | _], _), do: nil

  defp eval([v | mods], now) do
    with {:ok, jd, raw} <- parse(v, now) do
      Enum.reduce_while(mods, {jd, raw, false, true}, fn m, {jd, raw, sub, first} ->
        case modify(Value.to_text(m), jd, raw, first) do
          nil -> {:halt, nil}
          :subsec -> {:cont, {jd, nil, true, false}}
          jd2 -> {:cont, {jd2, nil, sub, false}}
        end
      end)
      |> case do
        nil -> nil
        {jd, _, sub, _} -> if jd < 0 or jd > 464_269_060_799_999, do: nil, else: {jd, sub}
      end
    else
      _ -> nil
    end
  end

  defp parse(v, _now) when is_integer(v) or is_float(v), do: {:ok, round(v * @day), v}
  defp parse({:blob, _}, _), do: :error

  defp parse(s, now) do
    t = String.trim(s)

    cond do
      String.downcase(t) == "now" ->
        {:ok, now + @unix_jd, nil}

      m =
          Regex.run(
            ~r/\A(-?\d{4})-(\d\d)-(\d\d)(?:[T ]+(\d\d):(\d\d)(?::(\d\d)(\.\d+)?)?)?\s*(Z|[+-]\d\d:\d\d)?\z/i,
            t
          ) ->
        from_parts(m)

      m = Regex.run(~r/\A(\d\d):(\d\d)(?::(\d\d)(\.\d+)?)?\s*(Z|[+-]\d\d:\d\d)?\z/i, t) ->
        [_, h, mi | rest] = m
        from_parts(["", "2000", "01", "01", h, mi | rest])

      n = Value.parse_number(t) ->
        {:ok, round(n * @day), n}

      true ->
        :error
    end
  end

  defp from_parts([_, y, mo, d | rest]) do
    [h, mi, s, frac, tz] = rest ++ List.duplicate("", 5 - length(rest))
    {y, mo, d} = {String.to_integer(y), String.to_integer(mo), String.to_integer(d)}
    {h, mi} = {int(h), int(mi)}
    sec = int(s) + if(frac == "", do: 0.0, else: String.to_float("0" <> frac))

    if mo in 1..12 and d in 1..31 and h in 0..24 and mi in 0..59 and sec < 60 do
      jd = jd_of(y, mo, d) + h * 3_600_000 + mi * 60_000 + trunc(sec * 1000 + 0.5)
      {:ok, jd - tz_minutes(tz) * 60_000, nil}
    else
      :error
    end
  end

  defp int(""), do: 0
  defp int(s), do: String.to_integer(s)

  defp tz_minutes(""), do: 0
  defp tz_minutes(z) when z in ["Z", "z"], do: 0

  defp tz_minutes(<<sign, h::binary-size(2), ":", m::binary-size(2)>>) do
    n = String.to_integer(h) * 60 + String.to_integer(m)
    if sign == ?-, do: -n, else: n
  end

  # computeJD, at midnight
  defp jd_of(y, m, d) do
    {y, m} = if m <= 2, do: {y - 1, m + 12}, else: {y, m}
    a = div(y, 100)
    b = 2 - a + div(a, 4)
    x1 = div(36525 * (y + 4716), 100)
    x2 = div(306_001 * (m + 1), 10000)
    trunc((x1 + x2 + d + b - 1524.5) * @day)
  end

  # computeYMD
  defp ymd(jd) do
    z = div(jd + 43_200_000, @day)
    a = trunc((z - 1_867_216.25) / 36524.25)
    a = z + 1 + a - div(a, 4)
    b = a + 1524
    c = trunc((b - 122.1) / 365.25)
    d = div(36525 * Bitwise.band(c, 32767), 100)
    e = trunc((b - d) / 30.6001)
    x1 = trunc(30.6001 * e)
    day = b - d - x1
    m = if e < 14, do: e - 1, else: e - 13
    y = if m > 2, do: c - 4716, else: c - 4715
    {y, m, day}
  end

  # computeHMS: hours, minutes, seconds (a float with the milliseconds)
  defp hms(jd) do
    ms = rem(jd + 43_200_000, @day)
    s = rem(ms, 60_000) / 1000
    mins = div(ms, 60_000)
    {div(mins, 60), rem(mins, 60), s}
  end

  defp time_ms(jd), do: rem(jd + 43_200_000, @day)

  # -- modifiers ---------------------------------------------------------------------------------

  defp modify(nil, _, _, _), do: nil

  defp modify(m, jd, raw, first) do
    m = m |> String.trim() |> String.downcase()

    cond do
      m == "unixepoch" and raw != nil and first ->
        round(raw * 1000) + @unix_jd

      m in ["utc", "localtime"] ->
        jd

      m in ["subsec", "subsecond"] ->
        :subsec

      m == "start of day" ->
        jd - time_ms(jd)

      m == "start of month" ->
        {y, mo, _} = ymd(jd)
        jd_of(y, mo, 1)

      m == "start of year" ->
        {y, _, _} = ymd(jd)
        jd_of(y, 1, 1)

      r = Regex.run(~r/\Aweekday (\d+)\z/, m) ->
        weekday(jd, String.to_integer(Enum.at(r, 1)))

      r =
          Regex.run(
            ~r/\A([+-]?\d+(?:\.\d*)?|[+-]?\.\d+)\s+(day|hour|minute|second|month|year)s?\z/,
            m
          ) ->
        add(jd, r)

      true ->
        nil
    end
  end

  defp weekday(_jd, n) when n > 6, do: nil

  defp weekday(jd, n) do
    z = rem(div(jd + 129_600_000, @day), 7)
    z = if z > n, do: z - 7, else: z
    jd + (n - z) * @day
  end

  defp add(jd, [_, num, unit]) do
    r = Value.parse_number(num) * 1.0

    {jd, r} =
      case unit do
        "month" ->
          {y, m, d} = ymd(jd)
          m = m + trunc(r)
          x = if m > 0, do: div(m - 1, 12), else: div(m - 12, 12)
          {jd_of(y + x, m - x * 12, d) + time_ms(jd), r - trunc(r)}

        "year" ->
          {y, m, d} = ymd(jd)
          {jd_of(y + trunc(r), m, d) + time_ms(jd), r - trunc(r)}

        _ ->
          {jd, r}
      end

    per = %{
      "second" => 1,
      "minute" => 60,
      "hour" => 3600,
      "day" => 86400,
      "month" => 2_592_000,
      "year" => 31_536_000
    }

    jd + trunc(r * 1000.0 * per[unit] + if(r < 0, do: -0.5, else: 0.5))
  end

  # -- output ------------------------------------------------------------------------------------

  defp fmt_date(jd) do
    {y, m, d} = ymd(jd)
    "#{pad(y, 4)}-#{pad(m, 2)}-#{pad(d, 2)}"
  end

  defp fmt_time(jd, subsec) do
    {h, m, s} = hms(jd)
    sec = if subsec, do: secs(s), else: pad(trunc(s), 2)
    "#{pad(h, 2)}:#{pad(m, 2)}:#{sec}"
  end

  defp fmt_datetime(jd, subsec), do: fmt_date(jd) <> " " <> fmt_time(jd, subsec)

  defp secs(s),
    do: :erlang.float_to_binary(min(s, 59.999), decimals: 3) |> String.pad_leading(6, "0")

  defp pad(n, w) when n < 0, do: "-" <> pad(-n, w)
  defp pad(n, w), do: n |> Integer.to_string() |> String.pad_leading(w, "0")

  defp spad(n), do: n |> Integer.to_string() |> String.pad_leading(2, " ")

  defp format("", _jd, acc), do: acc |> Enum.reverse() |> IO.iodata_to_binary()

  defp format("%" <> <<c, rest::binary>>, jd, acc) do
    {y, m, d} = ymd(jd)
    {h, mi, s} = hms(jd)
    after_mon = rem(div(jd + 43_200_000, @day), 7)
    after_sun = rem(div(jd + 129_600_000, @day), 7)
    yday = div(jd - jd_of(y, 1, 1) - time_ms(jd) + 43_200_000, @day)
    h12 = if rem(h, 12) == 0, do: 12, else: rem(h, 12)

    out =
      case c do
        ?d -> pad(d, 2)
        ?e -> spad(d)
        ?f -> secs(s)
        ?F -> fmt_date(jd)
        ?H -> pad(h, 2)
        ?I -> pad(h12, 2)
        ?k -> spad(h)
        ?l -> spad(h12)
        ?j -> pad(yday + 1, 3)
        ?J -> Moss.Sql.Printf.format(["%.16g", jd / @day])
        ?m -> pad(m, 2)
        ?M -> pad(mi, 2)
        ?p -> if h >= 12, do: "PM", else: "AM"
        ?P -> if h >= 12, do: "pm", else: "am"
        ?R -> "#{pad(h, 2)}:#{pad(mi, 2)}"
        ?s -> Integer.to_string(div(jd - @unix_jd, 1000))
        ?S -> pad(trunc(s), 2)
        ?T -> "#{pad(h, 2)}:#{pad(mi, 2)}:#{pad(trunc(s), 2)}"
        ?u -> Integer.to_string(after_mon + 1)
        ?w -> Integer.to_string(after_sun)
        ?W -> pad(div(yday - after_mon + 7, 7), 2)
        ?U -> pad(div(yday - after_sun + 7, 7), 2)
        ?Y -> pad(y, 4)
        ?G -> iso(y, m, d, :year)
        ?g -> iso(y, m, d, :year) |> String.slice(-2, 2)
        ?V -> iso(y, m, d, :week)
        ?% -> "%"
        _ -> nil
      end

    if out == nil, do: nil, else: format(rest, jd, [out | acc])
  end

  defp format(s, jd, acc) do
    case :binary.match(s, "%") do
      {at, _} -> format(binary_part(s, at, byte_size(s) - at), jd, [binary_part(s, 0, at) | acc])
      :nomatch -> format("", jd, [s | acc])
    end
  end

  defp iso(y, m, d, part) do
    {iy, w} = :calendar.iso_week_number({y, m, d})
    if part == :year, do: pad(iy, 4), else: pad(w, 2)
  rescue
    _ -> "00"
  end
end

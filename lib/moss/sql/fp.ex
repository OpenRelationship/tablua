defmodule Moss.Sql.Fp do
  @moduledoc """
  SQLite's own reals-to-decimal, ported from its source (3.53, util.c
  `sqlite3FpDecode` and `sqlite3Fp2Convert10`, printf.c's float conversions)
  so a real prints to the same digits here as in SQLite: an 18-digit
  approximation from a table of powers of ten, rounded half up, and the
  `%!.17g` rule that drops a 17th digit when fewer read back the same.
  A real becomes text by `%!.17g`; round() goes through `%!.*f`.
  """
  import Bitwise

  @base {0x8000000000000000, 0xA000000000000000, 0xC800000000000000, 0xFA00000000000000,
         0x9C40000000000000, 0xC350000000000000, 0xF424000000000000, 0x9896800000000000,
         0xBEBC200000000000, 0xEE6B280000000000, 0x9502F90000000000, 0xBA43B74000000000,
         0xE8D4A51000000000, 0x9184E72A00000000, 0xB5E620F480000000, 0xE35FA931A0000000,
         0x8E1BC9BF04000000, 0xB1A2BC2EC5000000, 0xDE0B6B3A76400000, 0x8AC7230489E80000,
         0xAD78EBC5AC620000, 0xD8D726B7177A8000, 0x878678326EAC9000, 0xA968163F0A57B400,
         0xD3C21BCECCEDA100, 0x84595161401484A0, 0xA56FA5B99019A5C8}
  @scale {0x8049A4AC0C5811AE, 0xCF42894A5DCE35EA, 0xA76C582338ED2621, 0x873E4F75E2224E68,
          0xDA7F5BF590966848, 0xB080392CC4349DEC, 0x8E938662882AF53E, 0xE65829B3046B0AFA,
          0xBA121A4650E4DDEB, 0x964E858C91BA2655, 0xF2D56790AB41C2A2, 0xC428D05AA4751E4C,
          0x9E74D1B791E07E48, 0xCCCCCCCCCCCCCCCC, 0xCECB8F27F4200F3A, 0xA70C3C40A64E6C51,
          0x86F0AC99B4E8DAFD, 0xDA01EE641A708DE9, 0xB01AE745B101E9E4, 0x8E41ADE9FBEBC27D,
          0xE5D3EF282A242E81, 0xB9A74A0637CE2EE1, 0x95F83D0A1FB69CD9, 0xF24A01A73CF2DCCF,
          0xC3B8358109E84F07, 0x9E19DB92B4E31BA9}
  @scale_lo {0x205B896D, 0x52064CAD, 0xAF2AF2B8, 0x5A7744A7, 0xAF39A475, 0xBD8D794E, 0x547EB47B,
             0x0CB4A5A3, 0x92F34D62, 0x3A6A07F9, 0xFAE27299, 0xAA97E14C, 0x775EA265, 0xCCCCCCCC,
             0x00000000, 0x999090B6, 0x69A028BB, 0xE80E6F48, 0x5EC05DD0, 0x14588F14, 0x8F1668C9,
             0x6D953E2C, 0x4ABDAF10, 0xBC633B39, 0x0A862F81, 0x6C07A2C2}

  @m64 0xFFFFFFFFFFFFFFFF

  @doc "A real as text, as SQLite stores it in a TEXT column or shows it with `||`: `%!.17g`."
  def text(r), do: format(r, ?g, 17, "!")

  @doc "round(r, n) for n > 0: `%!.*f`, read back."
  def round(r, n) do
    {v, _} = Float.parse(format(r, ?f, n, "!"))
    v
  end

  @doc """
  printf's `%f`, `%e`/`%E` and `%g`/`%G` of a real with `flags` (a string
  of `#`, `!`, `+`, space and `,`) and a precision: the text, without the
  field width.
  """
  def format(r, type, precision, flags) do
    alt = String.contains?(flags, "#")
    alt2 = String.contains?(flags, "!")
    thousands = String.contains?(flags, ",")

    sign_flag =
      cond do
        String.contains?(flags, "+") -> "+"
        String.contains?(flags, " ") -> " "
        true -> ""
      end

    kind =
      cond do
        type in [?f, ?F] -> :float
        type in [?e, ?E] -> :exp
        true -> :generic
      end

    {precision, iround} =
      case kind do
        :float ->
          {precision, -precision}

        :generic ->
          p = max(precision, 1)
          {p, p}

        :exp ->
          {precision, precision + 1}
      end

    {sign, z, n, idp} = decode(r, iround, if(alt2, do: 20, else: 16))

    prefix =
      if sign == ?-,
        do: if(alt and sign_flag == "" and kind == :float and idp <= iround, do: "", else: "-"),
        else: sign_flag

    exp = idp - 1

    {kind, precision, rtz} =
      if kind == :generic do
        p = precision - 1
        if exp < -4 or exp > p, do: {:exp, p, not alt}, else: {:float, p - exp, not alt}
      else
        {kind, precision, alt2}
      end

    e2 = if kind == :exp, do: 0, else: idp - 1
    dp = precision > 0 or alt or alt2
    digit = fn j -> if j < n, do: binary_part(z, j, 1), else: "0" end

    {int, j, e2} =
      cond do
        e2 < 0 ->
          {"0", 0, e2}

        thousands ->
          {Enum.map_join(e2..0//-1, fn k ->
             digit.(e2 - k) <> if(rem(k, 3) == 0 and k > 1, do: ",", else: "")
           end), min(e2 + 1, n), -1}

        true ->
          j = min(e2 + 1, n)
          {binary_part(z, 0, j) <> String.duplicate("0", max(e2 - j + 1, 0)), j, -1}
      end

    {lead, precision} =
      if e2 < -1 and precision > 0,
        do:
          (
            nn = min(-1 - e2, precision)
            {String.duplicate("0", nn), precision - nn}
          ),
        else: {"", precision}

    {frac, precision} =
      if precision > 0 do
        nn = max(min(n - j, precision), 0)
        {binary_part(z, j, nn), precision - nn}
      else
        {"", precision}
      end

    tail = if precision > 0 and not rtz, do: String.duplicate("0", precision), else: ""
    body = int <> if(dp, do: ".", else: "") <> lead <> frac <> tail

    body =
      if rtz and dp do
        b = String.trim_trailing(body, "0")

        if String.ends_with?(b, "."),
          do: if(alt2, do: b <> "0", else: String.trim_trailing(b, ".")),
          else: b
      else
        body
      end

    body =
      if kind == :exp do
        x = idp - 1
        e = if type in [?E, ?G], do: "E", else: "e"

        body <>
          e <>
          if(x < 0, do: "-", else: "+") <> String.pad_leading(Integer.to_string(abs(x)), 2, "0")
      else
        body
      end

    prefix <> body
  end

  @doc "sqlite3FpDecode: `{sign, digits, count, decimal point position}`."
  def decode(r, _iround, _mx) when r == 0, do: {?+, "0", 1, 1}

  def decode(r, iround, mx) do
    sign = if r < 0, do: ?-, else: ?+
    <<_::1, e::11, frac::52>> = <<abs(r)::float>>

    {m, e} =
      if e == 0 do
        nn = clz(frac)
        {frac <<< nn &&& @m64, -1074 - nn}
      else
        {(frac <<< 11 ||| 1 <<< 63) &&& @m64, e - 1086}
      end

    {d, exp} = convert10(m, e, if(iround <= 0 or iround >= 18, do: 18, else: iround + 1))
    z = Integer.to_string(d)
    n = byte_size(z)
    idp = n + exp

    {iround, z, n, idp} =
      if iround <= 0 do
        ir = idp - iround

        if ir == 0 and binary_part(z, 0, 1) >= "5",
          do: {1, "0" <> z, n + 1, idp + 1},
          else: {ir, z, n, idp}
      else
        {iround, z, n, idp}
      end

    {z, n, idp} =
      if iround > 0 and (iround < n or n > mx) do
        ir = min(iround, mx)
        ir = if ir == 17, do: shorter(r, z, n, exp, idp, ir), else: ir
        round_at(z, ir, idp)
      else
        {z, n, idp}
      end

    z = binary_part(z, 0, n) |> String.trim_trailing("0")
    {sign, z, byte_size(z), idp}
  end

  # %!.17g: fewer digits when they read back as the same real (49.47, not 49.469999999999999)
  defp shorter(r, z, n, exp, idp, ir) do
    at = fn k -> :binary.at(z, k) end

    cond do
      at.(15) == ?9 and at.(14) == ?9 ->
        jj =
          Enum.reduce_while(14..1//-1, 14, fn k, _ ->
            if at.(k - 1) == ?9, do: {:cont, k - 1}, else: {:halt, k}
          end)

        v2 = if jj == 0, do: 1, else: String.to_integer(binary_part(z, 0, jj)) + 1
        if back?(r, v2, exp + n - jj), do: jj + 1, else: ir

      idp >= n or (at.(15) == ?0 and at.(14) == ?0 and at.(13) == ?0) ->
        jj =
          Enum.reduce_while(13..1//-1, 13, fn k, _ ->
            if at.(k - 1) == ?0, do: {:cont, k - 1}, else: {:halt, k}
          end)

        v2 = String.to_integer(binary_part(z, 0, jj))
        if back?(r, v2, exp + n - jj), do: jj + 1, else: ir

      true ->
        ir
    end
  end

  defp back?(r, v2, p) do
    case Float.parse("#{v2}e#{p}") do
      {f, ""} -> f == abs(r)
      _ -> false
    end
  rescue
    _ -> false
  end

  # rounds the digits to `ir`, half up, carrying into a new leading 1
  defp round_at(z, ir, idp) do
    if binary_part(z, ir, 1) >= "5" do
      up = String.to_integer(binary_part(z, 0, ir)) + 1
      s = Integer.to_string(up) |> String.pad_leading(ir, "0")
      if byte_size(s) > ir, do: {s, ir + 1, idp + 1}, else: {s, ir, idp}
    else
      {z, ir, idp}
    end
  end

  defp clz(v), do: 64 - bit_length(v)
  defp bit_length(0), do: 0
  defp bit_length(v), do: length(Integer.digits(v, 2))

  defp pwr10to2(p), do: (p * 108_853) >>> 15
  defp pwr2to10(p), do: (p * 78913) >>> 18

  # sqlite3Fp2Convert10: m*2^e as d*10^p with at least n digits
  defp convert10(m, e, n) do
    p = n - 1 - pwr2to10(e + 63)
    {pow, _} = power_of_ten(p)
    h = (m * pow) >>> 64

    d =
      if n == 18 do
        h = h >>> -(e + pwr10to2(p) + 2)
        (h + (h <<< 1 &&& 2)) >>> 1
      else
        h >>> -(e + pwr10to2(p) + 1)
      end

    {d, -p}
  end

  # powerOfTen: the top 64 bits of 10^p, and the next 32
  defp power_of_ten(-1), do: {elem(@scale, 13), elem(@scale_lo, 13)}
  defp power_of_ten(p) when p >= 0 and p < 27, do: {elem(@base, p), 0}

  defp power_of_ten(p) do
    {g, n} = {div(p, 27), rem(p, 27)}
    {g, n} = if p < 0 and n != 0, do: {g - 1, n + 27}, else: {g, n}
    s = elem(@scale, g + 13)
    lo = elem(@scale_lo, g + 13)

    if n == 0 do
      {s, lo}
    else
      b = elem(@base, n)
      r = s * b + ((lo * b) >>> 32)
      x = r >>> 64
      lo = r >>> 32 &&& 0xFFFFFFFF

      if (x &&& 1 <<< 63) == 0,
        do: {(x <<< 1 ||| (lo >>> 31 &&& 1)) &&& @m64, (lo <<< 1 ||| 1) &&& 0xFFFFFFFF},
        else: {x, lo}
    end
  end
end

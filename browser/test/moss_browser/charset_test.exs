defmodule MossBrowser.CharsetTest do
  # A page's bytes as UTF-8: by its header, then its meta; windows-1252 decoded; a set not decoded is said.
  use ExUnit.Case, async: true

  alias MossBrowser.Charset

  test "UTF-8 passes, and windows-1252 is decoded by header or meta" do
    assert {"café", nil} = Charset.decode("café", "text/html; charset=utf-8")

    assert {"café “quoted”", nil} =
             Charset.decode(
               <<"caf", 0xE9, " ", 0x93, "quoted", 0x94>>,
               "text/html; charset=windows-1252"
             )

    page = <<"<meta charset=\"iso-8859-1\"><p>na", 0xEF, "ve</p>">>
    assert {text, nil} = Charset.decode(page, "text/html")
    assert text =~ "naïve"
  end

  test "a set it does not decode is said, not guessed" do
    assert {_, note} = Charset.decode(<<0x82, 0xA0>>, "text/html; charset=Shift_JIS")
    assert note =~ "Shift_JIS"
  end
end

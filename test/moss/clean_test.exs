defmodule Moss.CleanTest do
  # A page held to Shroomi's policy as it leaves the computer (Arock PROJECT.md §16): whatever the agent wrote,
  # nothing in it runs as script.
  use ExUnit.Case, async: true

  alias Moss.Computer.Clean

  defp clean(html), do: Clean.html(html)

  test "script in every form an agent might write is taken out" do
    out =
      clean(~S"""
      <p onclick="x()">hi<script>alert(1)</script><style>body{}</style></p>
      <img src=x onerror=alert(2)><iframe src="https://evil"></iframe><object data=x></object>
      <a href="javascript:alert(3)">a</a><a href=" JaVa&#x09;script:alert(4)">b</a><a href="https://ok.example/x">c</a>
      <form action="javascript:x"><button formaction="javascript:y">go</button></form>
      <div hx-on:click="alert(5)" hx-vars="alert(6)" hx-vals="js:{a: alert(7)}" hx-post="save" data-x="1" aria-label="l">d</div>
      <svg><foreignObject><script>alert(8)</script></foreignObject><path d="M0 0" onload="alert(9)"/></svg>
      <math><mi>x</mi></math><base href="https://evil/"><meta http-equiv="refresh" content="0;url=https://evil">
      <custom-thing>kept text</custom-thing><!-- a comment -->
      """)

    for bad <-
          ~w(onclick script style onerror iframe object javascript hx-on hx-vars hx-vals formaction foreignObject
                 onload math base meta comment evil) do
      refute out =~ bad, "#{bad} survived:\n#{out}"
    end

    assert out =~ ~s(<a href="https://ok.example/x">c</a>)
    assert out =~ ~s(<div hx-post="save" data-x="1" aria-label="l">d</div>)
    assert out =~ "kept text"
    assert out =~ ~s(<path d="M0 0"></path>)
    assert out =~ ~s(<img src="x"/>)
  end

  test "a whole page keeps Shroomi's shell and only the pinned assets" do
    out =
      clean(~S"""
      <!doctype html><html lang="en" class="dark" onload="x()"><head><meta charset="utf-8">
      <meta name="viewport" content="width=device-width"><meta http-equiv="refresh" content="0">
      <title>Plants <b>x</b></title><link rel="stylesheet" href="/shroomi/basecoat-1.0.2.min.css">
      <link rel="stylesheet" href="https://evil/x.css"><style>.p-4{padding:1rem}</style>
      <script src="/shroomi/htmx-2.0.4.min.js"></script><script src="/shroomi/shroomi.js" defer></script>
      <script src="/computers/x/app/mine.js"></script><script>alert(1)</script>
      </head><body class="p-4"><p>hi</p></body></html>
      """)

    assert out =~ ~s(<html lang="en" class="dark">)
    assert out =~ ~s(<meta charset="utf-8"/>)
    assert out =~ ~s(<link rel="stylesheet" href="/shroomi/basecoat-1.0.2.min.css"/>)
    assert out =~ ~s(<style>.p-4{padding:1rem}</style>)
    assert out =~ ~s(<script src="/shroomi/htmx-2.0.4.min.js"></script>)
    assert out =~ ~s(<script src="/shroomi/shroomi.js" defer=""></script>)
    assert out =~ ~s(<body class="p-4"><p>hi</p>)
    for bad <- ~w(evil refresh mine.js alert onload), do: refute(out =~ bad, bad)
  end

  test "a fragment for htmx stays a fragment" do
    assert clean(~s(<li class="x">fern <b onclick="y">!</b></li>)) ==
             ~s(<li class="x">fern <b>!</b></li>)
  end
end

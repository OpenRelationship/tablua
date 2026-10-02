defmodule Moonflower.Look.Faults do
  @moduledoc """
  What a look shows that a person could not use (Arock feature look), read from a look made by a module that
  says how each box is placed and painted (v0.2.0 on):

    * `:unseen`: a control (link, button, field) with no width or no height
    * `:covered`: a control whose middle is under a positioned element painted above it, so a click lands there
    * `:off_screen`: an element reaching past the screen's edge with nothing around it that scrolls or clips it
      (the outermost only; what is inside it is not named again)
    * `:faint`: text whose colour is under 4.5 to 1 against what is behind it

  Each fault is `%{kind:, id:, element: {tag, attrs, kids}}`, with `by:` and `by_id:` the covering element,
  `box:` the box, or `color:`, `background:` and `ratio:`. `id` is the element's mark in the look's tree; its
  attributes are the page's own, the mark kept off.
  """
  alias Moonflower.Page.Attrs

  @controls ~w(a button input select textarea summary)
  @min 4.5

  def faults(%Moonflower.Look{} = look) do
    els = look.tree |> elements(look, [], []) |> Enum.reverse()
    unseen(els) ++ covered(els) ++ off_screen(els, look.width) ++ faint(els, look.dark)
  end

  # every shown element with a box, last first, with the ids of the elements around it
  defp elements(nodes, look, up, acc) do
    Enum.reduce(nodes, acc, fn
      {tag, attrs, kids} = node, acc when is_binary(tag) ->
        id = Attrs.attr(attrs, "data-mf")
        box = look.shown[id]

        acc =
          if is_map(box) and Map.has_key?(box, :z),
            do: [entry(node, id, box, up) | acc],
            else: acc

        elements(kids, look, [id | up], acc)

      _, acc ->
        acc
    end)
  end

  defp entry({tag, attrs, kids}, id, box, up) do
    %{
      id: id,
      tag: tag,
      element: {tag, List.keydelete(attrs, "data-mf", 0), kids},
      box: box,
      up: up,
      control: control?(tag, attrs),
      text: Enum.any?(kids, &(is_binary(&1) and String.trim(&1) != ""))
    }
  end

  defp control?("input", attrs), do: Attrs.attr(attrs, "type") != "hidden"
  defp control?("a", attrs), do: Attrs.attr(attrs, "href") != nil
  defp control?(tag, _), do: tag in @controls

  defp unseen(els) do
    for e <- els,
        e.control,
        e.box.w == 0 or e.box.h == 0,
        do: %{kind: :unseen, id: e.id, element: e.element, box: e.box}
  end

  # a positioned element above the control's middle, not around it nor inside it, painted later or higher
  defp covered(els) do
    order = els |> Enum.with_index() |> Map.new(fn {e, i} -> {e.id, i} end)
    byid = Map.new(els, &{&1.id, &1})

    for c <- els,
        c.control,
        c.box.w > 0 and c.box.h > 0,
        {cx, cy} = {c.box.x + div(c.box.w, 2), c.box.y + div(c.box.h, 2)},
        o =
          Enum.find(els, fn o ->
            o.box.position != "s" and o.id != c.id and o.id not in c.up and c.id not in o.up and
              inside?(o.box, cx, cy) and above?(o, c, order, byid)
          end),
        do: %{kind: :covered, id: c.id, element: c.element, by: o.element, by_id: o.id}
  end

  defp inside?(b, x, y), do: x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h

  defp above?(o, c, order, byid) do
    {zo, zc} = {z(o, byid), z(c, byid)}
    zo > zc or (zo == zc and order[o.id] > order[c.id])
  end

  # the z-index the element paints at: its own, or that of the nearest positioned element around it
  defp z(e, byid) do
    Enum.find_value([e | Enum.map(e.up, &byid[&1])], 0, fn
      %{box: %{z: z}} when is_integer(z) -> z
      _ -> nil
    end)
  end

  defp off_screen(els, width) do
    clipping = for e <- els, e.box.clips, into: MapSet.new(), do: e.id

    els
    |> Enum.filter(fn e ->
      (e.box.x < -1 or e.box.x + e.box.w > width + 1) and e.box.w > 1 and
        not Enum.any?(e.up, &MapSet.member?(clipping, &1))
    end)
    |> then(fn off ->
      named = MapSet.new(off, & &1.id)

      for e <- off,
          not Enum.any?(e.up, &MapSet.member?(named, &1)),
          do: %{kind: :off_screen, id: e.id, element: e.element, box: e.box}
    end)
  end

  defp faint(els, dark) do
    byid = Map.new(els, &{&1.id, &1})
    canvas = if dark, do: {0, 0, 0}, else: {255, 255, 255}

    for e <- els,
        e.text,
        e.box.w > 0 and e.box.h > 0,
        back = behind(e, byid, canvas),
        fore = over(e.box.color, back),
        ratio = ratio(fore, back),
        ratio < @min,
        do: %{
          kind: :faint,
          id: e.id,
          element: e.element,
          color: hex(fore),
          background: hex(back),
          ratio: Float.round(ratio, 1)
        }
  end

  # the colour behind an element: its background and those around it, laid over each other on the canvas
  defp behind(e, byid, canvas) do
    [e | Enum.map(e.up, &byid[&1])]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(& &1.box.background)
    |> Enum.reverse()
    |> Enum.reduce(canvas, &over/2)
  end

  defp over({r, g, b, 255}, _), do: {r, g, b}
  defp over({_, _, _, 0}, back), do: back

  defp over({r, g, b, a}, {br, bg, bb}) do
    t = a / 255
    {round(r * t + br * (1 - t)), round(g * t + bg * (1 - t)), round(b * t + bb * (1 - t))}
  end

  defp ratio(a, b) do
    {la, lb} = {luminance(a), luminance(b)}
    (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
  end

  defp luminance({r, g, b}), do: 0.2126 * lin(r) + 0.7152 * lin(g) + 0.0722 * lin(b)

  defp lin(c) do
    c = c / 255
    if c <= 0.03928, do: c / 12.92, else: :math.pow((c + 0.055) / 1.055, 2.4)
  end

  defp hex({r, g, b}), do: "#" <> Base.encode16(<<r, g, b>>, case: :lower)
end

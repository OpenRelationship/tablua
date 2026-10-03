defmodule MossBrowser.Fetch.Body do
  @moduledoc """
  An answer's body as it streams in (Req's `into:`), held to `max` bytes. When the browser asked for gzip or
  deflate, the body is inflated as it comes, a little at a time (`:zlib.safeInflate`), and the cap counts the
  inflated bytes, so a small answer cannot grow past it. Past the cap the answer either stops with an error
  (curl's way) or, `cut: true`, keeps what fit and says so (the browser's).

      Req.request(..., into: Body.into(max, cut: true, inflate: true))
      {:ok, body, cut?} = Body.finish(resp)
  """

  def into(max, opts \\ []) do
    cut = Keyword.get(opts, :cut, false)
    inflate = Keyword.get(opts, :inflate, false)

    fn {:data, data}, {req, resp} ->
      b = Map.get(resp.private, :body, %{acc: [], size: 0, z: :none})
      b = if b.z == :none, do: %{b | z: opener(inflate, resp)}, else: b

      case chunk(b.z, data, max - b.size + 1) do
        {:ok, out} ->
          keep(b, out, max, cut, req, resp)

        :bad ->
          {:halt,
           {req,
            Req.Response.put_private(resp, :body, %{b | z: close(b.z)} |> Map.put(:bad, true))}}
      end
    end
  end

  def finish(resp) do
    case Map.get(resp.private, :body) do
      nil ->
        {:ok, if(is_binary(resp.body), do: resp.body, else: ""), false}

      %{bad: true} ->
        {:error, "the answer's compression is broken"}

      %{too_big: max} ->
        {:error, {:too_big, max}}

      b ->
        close(b.z)
        {:ok, b.acc |> Enum.reverse() |> IO.iodata_to_binary(), Map.get(b, :cut, false)}
    end
  end

  defp keep(b, out, max, cut, req, resp) do
    size = b.size + byte_size(out)

    cond do
      size <= max ->
        {:cont,
         {req, Req.Response.put_private(resp, :body, %{b | acc: [out | b.acc], size: size})}}

      cut ->
        part = binary_part(out, 0, max - b.size)
        b = %{b | acc: [part | b.acc], size: max, z: close(b.z)} |> Map.put(:cut, true)
        {:halt, {req, Req.Response.put_private(resp, :body, b)}}

      true ->
        {:halt,
         {req,
          Req.Response.put_private(
            resp,
            :body,
            %{b | acc: [], z: close(b.z)} |> Map.put(:too_big, max)
          )}}
    end
  end

  defp opener(false, _resp), do: nil

  defp opener(true, resp) do
    case resp
         |> Req.Response.get_header("content-encoding")
         |> List.first()
         |> to_string()
         |> String.downcase() do
      e when e in ["gzip", "x-gzip", "deflate"] ->
        z = :zlib.open()
        # 47: a gzip or a zlib header, whichever it has
        :ok = :zlib.inflateInit(z, 47)
        z

      _ ->
        nil
    end
  end

  # at most `room` inflated bytes from this chunk (a little more, which keep/6 cuts)
  defp chunk(nil, data, _room), do: {:ok, data}

  defp chunk(z, data, room) do
    inflate(z, :zlib.safeInflate(z, data), room, [])
  rescue
    ErlangError -> :bad
  end

  defp inflate(z, {:continue, out}, room, acc) do
    acc = [acc, out]

    if IO.iodata_length(acc) > room,
      do: {:ok, IO.iodata_to_binary(acc)},
      else: inflate(z, :zlib.safeInflate(z, []), room, acc)
  end

  defp inflate(_z, {:finished, out}, _room, acc), do: {:ok, IO.iodata_to_binary([acc, out])}
  defp inflate(_z, _, _room, acc), do: {:ok, IO.iodata_to_binary(acc)}

  defp close(z) when z in [nil, :none], do: nil

  defp close(z) do
    :zlib.close(z)
    nil
  rescue
    _ -> nil
  end
end

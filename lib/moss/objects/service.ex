defmodule Moss.Objects.Service do
  @moduledoc """
  Sleeping computers' disks kept through Arock's service (`/moss/disks/<id>`,
  Arock's `app/worker/src/disks.ts`), with this node's own token: the node
  holds no key to the bucket or the Cloudflare account, and the service serves
  it only the disks it claimed (Arock PROJECT.md §14.7, goal 2).

  The token is MOSS_NODE_TOKEN or the keychain item `moss-node-token`; the
  service is MOSS_SERVICE or https://arock.ai. A disk over #{div(64 * 1024 * 1024, 1_048_576)} MB goes up in
  #{div(32 * 1024 * 1024, 1_048_576)} MB parts. The token is never logged, printed, written or put in an error.
  Only computers' disks (`computers/<id>.sqlite`) are kept here.
  """
  @behaviour Moss.Objects

  @whole 64 * 1024 * 1024
  @part 32 * 1024 * 1024

  @impl true
  def get(key) do
    with {:ok, path} <- path(key) do
      case request(:get, path, nil) do
        {:ok, 200, body} -> {:ok, body}
        {:ok, 404, _} -> :not_found
        other -> failure(other)
      end
    end
  end

  @impl true
  def put(key, body) do
    if byte_size(body) <= Application.get_env(:moss, :service_whole_bytes, @whole),
      do: put_whole(key, body),
      else: put_parts(key, body)
  end

  defp put_whole(key, body) do
    with {:ok, path} <- path(key), do: done(request(:put, path, body))
  end

  defp put_parts(key, body) do
    with {:ok, path} <- path(key),
         {:ok, 200, %{"upload" => upload}} <- json(request(:post, path <> "/uploads", nil)),
         {:ok, parts} <- parts(path <> "/uploads/" <> upload, body, 1, []) do
      done(request(:post, path <> "/uploads/#{upload}/complete", Jason.encode!(%{parts: parts})))
    else
      {:error, _} = e -> e
      other -> failure(other)
    end
  end

  @impl true
  def delete(key) do
    with {:ok, path} <- path(key) do
      case request(:delete, path, nil) do
        {:ok, s, _} when s in 200..299 or s == 404 -> :ok
        other -> failure(other)
      end
    end
  end

  @doc "Whether this node has a token, so the service can be used at all."
  def available?, do: token() != nil

  @doc "The request as sent; exposed so tests can check it offline."
  def build(method, path, body, token) do
    Req.new(
      [
        method: method,
        url: base() <> "/moss/disks/" <> path,
        body: body,
        auth: {:bearer, token},
        headers: [{"content-type", "application/octet-stream"}],
        retry: false,
        decode_body: false,
        receive_timeout: 120_000
      ] ++ Application.get_env(:moss, :service_req_options, [])
    )
  end

  defp parts(_at, "", _n, acc), do: {:ok, Enum.reverse(acc)}

  defp parts(at, body, n, acc) do
    size = Application.get_env(:moss, :service_part_bytes, @part)

    {chunk, rest} =
      if byte_size(body) > size, do: :erlang.split_binary(body, size), else: {body, ""}

    case json(request(:put, "#{at}/#{n}", chunk)) do
      {:ok, 200, %{"etag" => etag}} -> parts(at, rest, n + 1, [%{part: n, etag: etag} | acc])
      other -> failure(other)
    end
  end

  # computers/<id>.sqlite -> <id>, the only keys the service keeps
  defp path("computers/" <> file) do
    if String.ends_with?(file, ".sqlite"),
      do: {:ok, String.trim_trailing(file, ".sqlite")},
      else: {:error, "the service keeps only computers' disks"}
  end

  defp path(_), do: {:error, "the service keeps only computers' disks"}

  defp request(method, path, body) do
    case token() do
      nil ->
        {:error, :no_token}

      token ->
        case Req.request(build(method, path, body, token)) do
          {:ok, %{status: status, body: resp}} -> {:ok, status, resp}
          {:error, e} -> {:error, Exception.message(e)}
        end
    end
  end

  defp json({:ok, status, body}) do
    case Jason.decode(body) do
      {:ok, v} -> {:ok, status, v}
      _ -> {:ok, status, body}
    end
  end

  defp json(other), do: other

  defp done({:ok, s, _}) when s in 200..299, do: :ok
  defp done(other), do: failure(other)

  defp failure({:ok, status, body}),
    do: {:error, "the service answered #{status}: #{String.slice(to_string(body), 0, 200)}"}

  defp failure({:error, _} = e), do: e
  defp failure(other), do: {:error, inspect(other)}

  defp token,
    do: present(System.get_env("MOSS_NODE_TOKEN")) || Moss.Keys.keychain("moss-node-token")

  defp base, do: present(System.get_env("MOSS_SERVICE")) || "https://arock.ai"

  defp present(s) when is_binary(s) and s != "", do: s
  defp present(_), do: nil
end

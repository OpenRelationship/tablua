defmodule Moss.FakeService do
  @moduledoc "Arock's /moss/disks, /moss/packs and /moss/logs (read only), played in memory, by the node's token."

  @doc """
  A plug for `service_req_options`: tells `test` each request as
  `{:asked, method, path, authorization}`. Options: `store`, an Agent holding
  what the service holds (`{:log, id, name}` keys are a log from before packs,
  `{:pack, node, name}` a pack), and `refuse`, a function of the method and
  path that answers 500 when it is true.
  """
  def plug(test, opts \\ []) do
    store = opts[:store] || elem(Agent.start_link(fn -> %{} end), 1)
    refuse = opts[:refuse] || fn _, _ -> false end

    fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn, length: 1_000_000_000)

      send(
        test,
        {:asked, conn.method, conn.request_path, Plug.Conn.get_req_header(conn, "authorization")}
      )

      if refuse.(conn.method, conn.request_path) do
        Plug.Conn.send_resp(conn, 500, "refused")
      else
        case String.split(conn.request_path, "/", trim: true) do
          ["moss", "logs" | rest] -> fake_logs(conn, store, rest)
          ["moss", "packs" | rest] -> fake_packs(conn, store, rest, body)
          ["moss", "disks", id | rest] -> fake_disks(conn, store, id, rest, body)
        end
      end
    end
  end

  # /moss/logs: a computer's segments from before packs, listed and read as the service does, never written
  defp fake_logs(%{method: "GET"} = conn, store, [id]) do
    segments =
      for {{:log, ^id, name}, body} <- Agent.get(store, & &1),
          do: %{name: name, size: byte_size(body)}

    Plug.Conn.send_resp(conn, 200, Jason.encode!(%{segments: Enum.sort_by(segments, & &1.name)}))
  end

  defp fake_logs(%{method: "GET"} = conn, store, [id, level, file]) do
    case Agent.get(store, &Map.get(&1, {:log, id, level <> "/" <> file})) do
      nil -> Plug.Conn.send_resp(conn, 404, "{}")
      seg -> Plug.Conn.send_resp(conn, 200, seg)
    end
  end

  defp fake_logs(conn, _store, _), do: Plug.Conn.send_resp(conn, 405, "read only")

  # /moss/packs/<node>: a node's packs, a Range header read as the service reads it
  defp fake_packs(conn, store, [node], _body) do
    packs =
      for {{:pack, ^node, name}, body} <- Agent.get(store, & &1),
          do: %{name: name, size: byte_size(body)}

    Plug.Conn.send_resp(conn, 200, Jason.encode!(%{packs: Enum.sort_by(packs, & &1.name)}))
  end

  defp fake_packs(conn, store, [node, name], body) do
    key = {:pack, node, name}

    case conn.method do
      "PUT" ->
        Agent.update(store, &Map.put(&1, key, body))
        Plug.Conn.send_resp(conn, 204, "")

      "GET" ->
        case {Agent.get(store, &Map.get(&1, key)), Plug.Conn.get_req_header(conn, "range")} do
          {nil, _} -> Plug.Conn.send_resp(conn, 404, "{}")
          {pack, []} -> Plug.Conn.send_resp(conn, 200, pack)
          {pack, ["bytes=" <> r]} -> Plug.Conn.send_resp(conn, 206, part(pack, r))
        end

      "DELETE" ->
        Agent.update(store, &Map.delete(&1, key))
        Plug.Conn.send_resp(conn, 204, "")
    end
  end

  defp part(pack, range) do
    {first, last} =
      case String.split(range, "-") do
        [a, ""] -> {String.to_integer(a), byte_size(pack) - 1}
        [a, b] -> {String.to_integer(a), min(String.to_integer(b), byte_size(pack) - 1)}
      end

    binary_part(pack, first, max(last - first + 1, 0))
  end

  defp fake_disks(conn, store, id, rest, body) do
    case {conn.method, rest} do
      {"GET", []} ->
        case Agent.get(store, &Map.get(&1, id)) do
          nil -> Plug.Conn.send_resp(conn, 404, "{}")
          disk -> Plug.Conn.send_resp(conn, 200, disk)
        end

      {"PUT", []} ->
        Agent.update(store, &Map.put(&1, id, body))
        Plug.Conn.send_resp(conn, 204, "")

      {"DELETE", []} ->
        Agent.update(store, &Map.delete(&1, id))
        Plug.Conn.send_resp(conn, 204, "")

      {"POST", ["uploads"]} ->
        Plug.Conn.send_resp(conn, 200, ~s({"upload":"u1"}))

      {"PUT", ["uploads", "u1", n]} ->
        Agent.update(store, &Map.put(&1, {id, String.to_integer(n)}, body))
        Plug.Conn.send_resp(conn, 200, ~s({"etag":"e#{n}"}))

      {"POST", ["uploads", "u1", "complete"]} ->
        %{"parts" => parts} = Jason.decode!(body)

        whole =
          Enum.map_join(parts, fn %{"part" => n, "etag" => "e" <> m} ->
            ^m = to_string(n)
            Agent.get(store, &Map.fetch!(&1, {id, n}))
          end)

        Agent.update(store, &Map.put(&1, id, whole))
        Plug.Conn.send_resp(conn, 204, "")
    end
  end
end

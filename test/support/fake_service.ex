defmodule Moss.FakeService do
  @moduledoc "Arock's /moss/disks and /moss/logs, played in memory: whole disks, disks in parts and log segments, by the node's token."

  @doc """
  A plug for `service_req_options`: tells `test` each request as
  `{:asked, method, path, authorization}`; a log segment whose name is in
  `fail` is refused with a 500.
  """
  def plug(test, fail \\ []) do
    {:ok, store} = Agent.start_link(fn -> %{} end)

    fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn, length: 1_000_000_000)

      send(
        test,
        {:asked, conn.method, conn.request_path, Plug.Conn.get_req_header(conn, "authorization")}
      )

      case String.split(conn.request_path, "/", trim: true) do
        ["moss", "logs" | rest] ->
          if conn.method == "PUT" and Enum.join(Enum.drop(rest, 1), "/") in fail,
            do: Plug.Conn.send_resp(conn, 500, "refused"),
            else: fake_logs(conn, store, rest, body)

        ["moss", "disks", id | rest] ->
          fake_disks(conn, store, id, rest, body)
      end
    end
  end

  # /moss/logs: a computer's segments, listed as the service lists them
  defp fake_logs(conn, store, [id], _body) do
    segments =
      for {{:log, ^id, name}, body} <- Agent.get(store, & &1),
          do: %{name: name, size: byte_size(body)}

    Plug.Conn.send_resp(conn, 200, Jason.encode!(%{segments: Enum.sort_by(segments, & &1.name)}))
  end

  defp fake_logs(conn, store, [id, level, file], body) do
    key = {:log, id, level <> "/" <> file}

    case conn.method do
      "PUT" ->
        Agent.update(store, &Map.put(&1, key, body))
        Plug.Conn.send_resp(conn, 204, "")

      "GET" ->
        case Agent.get(store, &Map.get(&1, key)) do
          nil -> Plug.Conn.send_resp(conn, 404, "{}")
          seg -> Plug.Conn.send_resp(conn, 200, seg)
        end

      "DELETE" ->
        Agent.update(store, &Map.delete(&1, key))
        Plug.Conn.send_resp(conn, 204, "")
    end
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

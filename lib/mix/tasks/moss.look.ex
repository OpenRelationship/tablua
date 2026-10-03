defmodule Mix.Tasks.Moss.Look do
  @shortdoc "Fetches the look module, the release pinned in config"
  @moduledoc """
  Fetches `look.wasm` from the GitHub release named in config `:look` (`repo`, `release`), checks it against the
  pinned SHA-384 and writes it to `path`. A file already there with that hash is kept. The repository is private, so
  the request carries GITHUB_TOKEN when it is set; the token is sent to GitHub only, never printed or written.

      GITHUB_TOKEN=... mix moss.look
  """
  use Mix.Task

  @asset "look.wasm"

  @impl true
  def run(_argv) do
    Mix.Task.run("app.config")
    Application.ensure_all_started(:req)
    %{repo: repo, release: tag, sha384: sha, path: path} = Map.new(Application.fetch_env!(:moss, :look))

    if File.exists?(path) and hash(File.read!(path)) == sha do
      Mix.shell().info("look: #{path} is #{tag}")
    else
      bytes = fetch(repo, tag)
      got = hash(bytes)

      if got != sha,
        do: Mix.raise("look: #{repo} #{tag}'s #{@asset} is #{got}, not the pinned #{sha}")

      File.mkdir_p!(Path.dirname(path))
      File.write!(path, bytes)
      Mix.shell().info("look: #{tag} written to #{path} (#{div(byte_size(bytes), 1024)} KB)")
    end
  end

  defp fetch(repo, tag) do
    api = "https://api.github.com/repos/#{repo}"

    with {:ok, %{status: 200, body: %{"assets" => assets}}} <-
           Req.get(api <> "/releases/tags/#{tag}",
             headers: headers("application/vnd.github+json")
           ),
         %{"url" => url} <- Enum.find(assets, &(&1["name"] == @asset)),
         {:ok, %{status: 200, body: bytes}} when is_binary(bytes) <-
           Req.get(url, headers: headers("application/octet-stream"), decode_body: false) do
      bytes
    else
      # only the status: an error from Req may carry the request, and with it the token
      {:ok, %{status: status}} ->
        Mix.raise("look: GitHub answered #{status} for #{repo} #{tag}" <> hint(status))

      nil ->
        Mix.raise("look: #{repo} #{tag} has no #{@asset}")

      {:error, %{__exception__: true} = e} ->
        Mix.raise("look: #{e.__struct__} fetching #{repo} #{tag}")
    end
  end

  defp hint(404), do: " (a private repository: set GITHUB_TOKEN)"
  defp hint(_), do: ""

  defp headers(accept) do
    auth =
      case System.get_env("GITHUB_TOKEN") do
        t when t in [nil, ""] -> []
        t -> [{"authorization", "Bearer " <> t}]
      end

    [{"accept", accept}, {"x-github-api-version", "2022-11-28"} | auth]
  end

  defp hash(bytes), do: :crypto.hash(:sha384, bytes) |> Base.encode16(case: :lower)
end

defmodule VolvoxServer.Keys do
  @moduledoc """
  Model keys for the ports, from the environment first, then the macOS
  keychain: `jev` is OPENROUTER_API_KEY (Jev goes through OpenRouter);
  `mercury` is INCEPTION_API_KEY or the keychain item `volvox-inception`, the
  same item Volvox's ports-live tool reads. A key is returned to the caller
  only; it is never logged, printed or written anywhere.
  """

  @sources %{
    "jev" => {"OPENROUTER_API_KEY", nil},
    "mercury" => {"INCEPTION_API_KEY", "volvox-inception"}
  }

  def get(name) do
    case Map.fetch(@sources, name) do
      {:ok, {env, item}} -> present(System.get_env(env)) || keychain(item)
      :error -> nil
    end
  end

  @doc "A generic password from the login keychain, or nil."
  def keychain(nil), do: nil

  def keychain(item) do
    case System.cmd("security", ["find-generic-password", "-s", item, "-w"],
           stderr_to_stdout: true
         ) do
      {out, 0} -> present(String.trim(out))
      _ -> nil
    end
  rescue
    ErlangError -> nil
  end

  defp present(""), do: nil
  defp present(v), do: v
end

defmodule Moonflower.Look.Module do
  @moduledoc """
  The look's WebAssembly module, loaded once: its bytes checked against the SHA-384 the caller pins, then compiled
  ahead for an engine that counts fuel. A look instantiates it fresh each time (`Moonflower.Look.Run`).
  """

  @doc "`{:ok, %{engine, precompiled}}`, or `{:error, :hash}` when the bytes are not the pinned module."
  def load(path, sha384) do
    with {:ok, bytes} <- File.read(path),
         :ok <- check(bytes, sha384) do
      engine = Wasmex.Engine.new(Wasmex.EngineConfig.consume_fuel(%Wasmex.EngineConfig{}, true))
      {:ok, engine} = engine
      {:ok, precompiled} = Wasmex.Engine.precompile_module(engine, bytes)
      {:ok, %{engine: engine, precompiled: precompiled}}
    end
  end

  defp check(bytes, sha384) do
    got = :crypto.hash(:sha384, bytes) |> Base.encode16(case: :lower)
    if got == String.downcase(sha384 || ""), do: :ok, else: {:error, :hash}
  end
end

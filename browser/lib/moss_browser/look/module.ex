defmodule MossBrowser.Look.Module do
  @moduledoc """
  The look's WebAssembly module, loaded once: its bytes checked against the SHA-384 the caller pins, then compiled
  (optimised, for an engine that counts fuel) and kept compiled. A look instantiates it fresh each time
  (`MossBrowser.Look.Run`); compiling or deserialising it per look cost more than the look, and serialised the
  looks running at once on mapping executable memory.
  """

  @doc "`{:ok, %{engine, module}}`, or `{:error, :hash}` when the bytes are not the pinned module."
  def load(path, sha384) do
    with {:ok, bytes} <- File.read(path),
         :ok <- check(bytes, sha384) do
      config =
        %Wasmex.EngineConfig{}
        |> Wasmex.EngineConfig.consume_fuel(true)
        |> Wasmex.EngineConfig.cranelift_opt_level(:speed)

      {:ok, engine} = Wasmex.Engine.new(config)
      {:ok, precompiled} = Wasmex.Engine.precompile_module(engine, bytes)
      {:ok, module} = Wasmex.Module.unsafe_deserialize(precompiled, engine)
      {:ok, %{engine: engine, module: module}}
    end
  end

  defp check(bytes, sha384) do
    got = :crypto.hash(:sha384, bytes) |> Base.encode16(case: :lower)
    if got == String.downcase(sha384 || ""), do: :ok, else: {:error, :hash}
  end
end

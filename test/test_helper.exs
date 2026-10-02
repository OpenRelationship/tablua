# The look's tests need the module CI builds (priv/look.wasm); without it they are left out, and said so.
if File.exists?(Path.expand("../priv/look.wasm", __DIR__)) do
  ExUnit.start()
else
  IO.puts("priv/look.wasm is not here: the look's tests are left out (CI builds it; see README)")
  ExUnit.start(exclude: [:look])
end

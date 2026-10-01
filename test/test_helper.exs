# Runs, their objects and the node's books start empty on every test run: the
# app is stopped first, so nothing holds a file in them while they go.
Application.stop(:moss)

for dir <- [:work_dir, :local_objects, :host_dir],
    do: File.rm_rf!(Application.fetch_env!(:moss, dir))

{:ok, _} = Application.ensure_all_started(:moss)
ExUnit.start(exclude: [:r2])

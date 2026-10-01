# Runs, their objects and the node's books start empty on every test run: the
# app is stopped first, so nothing holds a file in them while they go.
Application.stop(:volvox_server)

for dir <- [:work_dir, :local_objects, :host_dir],
    do: File.rm_rf!(Application.fetch_env!(:volvox_server, dir))

{:ok, _} = Application.ensure_all_started(:volvox_server)
ExUnit.start(exclude: [:r2])
